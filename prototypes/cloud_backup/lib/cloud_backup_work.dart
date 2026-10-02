import 'dart:io';

import 'package:encrypted_storage_probe/encrypted_database.dart';
import 'package:persistent_jobs_probe/persistent_jobs.dart';
import 'package:sqlite3/sqlite3.dart';

import 'cloud_backup.dart';
import 'google_drive_adapter.dart';

const cloudBackupUploadJobKind = 'backup.upload.v1';
const _jobPrefix = 'cloud-backup:';

enum CloudBackupWorkState { staged, uploaded }

enum CloudBackupWorkFailure {
  authenticationRequired,
  permissionDenied,
  quotaExceeded,
  throttled,
  unavailable,
  uncertainResult,
  integrityRejected,
  temporaryLocalFailure,
}

final class CloudBackupWorkRecord {
  const CloudBackupWorkRecord({
    required this.backupId,
    required this.providerId,
    required this.sha256,
    required this.byteLength,
    required this.createdAt,
    required this.updatedAt,
    required this.fileName,
    required this.state,
    this.scheduledFor,
    this.remoteObjectId,
    this.lastFailure,
  });

  final String backupId;
  final String providerId;
  final String sha256;
  final int byteLength;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? scheduledFor;
  final String fileName;
  final CloudBackupWorkState state;
  final String? remoteObjectId;
  final CloudBackupWorkFailure? lastFailure;
}

/// SQLCipher metadata plus an immutable, already-encrypted envelope file.
/// Tokens and unlock credentials are never stored here.
final class CloudBackupWorkStore implements DriveReservationStore {
  CloudBackupWorkStore._(this._db, this.artifactDirectory);

  final Database _db;
  final Directory artifactDirectory;

  static CloudBackupWorkStore open({
    required File databaseFile,
    required Directory artifactDirectory,
    required StorageKey key,
  }) {
    final parent = databaseFile.parent;
    if (FileSystemEntity.typeSync(parent.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw StateError('Cloud backup database parent must be a directory');
    }
    final artifactType = FileSystemEntity.typeSync(
      artifactDirectory.path,
      followLinks: false,
    );
    if (artifactType == FileSystemEntityType.notFound) {
      artifactDirectory.createSync(recursive: true);
    } else if (artifactType != FileSystemEntityType.directory) {
      throw StateError('Cloud backup artifact path must be a directory');
    }
    final db = sqlite3.open(databaseFile.path);
    try {
      configureEncryption(db, key);
      db.execute('PRAGMA journal_mode=DELETE');
      db.execute('PRAGMA synchronous=FULL');
      db.execute('PRAGMA busy_timeout=10000');
      if (db.userVersion == 0) {
        final existing = db.select(
          "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
        );
        if (existing.isNotEmpty)
          throw StateError('Unknown cloud backup schema');
        db.execute('BEGIN IMMEDIATE');
        try {
          db.execute('''
            CREATE TABLE backup_work (
              backup_id TEXT PRIMARY KEY,
              provider_id TEXT NOT NULL,
              sha256 TEXT NOT NULL,
              byte_length INTEGER NOT NULL CHECK(byte_length > 0),
              created_at INTEGER NOT NULL,
              scheduled_for INTEGER,
              file_name TEXT NOT NULL UNIQUE,
              state TEXT NOT NULL CHECK(state IN ('staged','uploaded')),
              remote_object_id TEXT UNIQUE,
              last_failure TEXT CHECK(last_failure IN (
                'authenticationRequired','permissionDenied','quotaExceeded',
                'throttled','unavailable','uncertainResult',
                'integrityRejected','temporaryLocalFailure'
              )),
              updated_at INTEGER NOT NULL
            ) STRICT
          ''');
          db.execute('CREATE INDEX backup_work_state ON backup_work(state)');
          db.execute('PRAGMA user_version=3');
          db.execute('COMMIT');
        } catch (_) {
          db.execute('ROLLBACK');
          rethrow;
        }
      } else {
        if (db.userVersion == 1) {
          db.execute('BEGIN IMMEDIATE');
          try {
            db.execute('''
            ALTER TABLE backup_work ADD COLUMN last_failure TEXT CHECK(
              last_failure IN (
                'authenticationRequired','permissionDenied','quotaExceeded',
                'throttled','unavailable','uncertainResult',
                'integrityRejected','temporaryLocalFailure'
              )
            )
          ''');
            db.execute('PRAGMA user_version=2');
            db.execute('COMMIT');
          } catch (_) {
            db.execute('ROLLBACK');
            rethrow;
          }
        }
        if (db.userVersion == 2) {
          db.execute('BEGIN IMMEDIATE');
          try {
            db.execute(
              'ALTER TABLE backup_work ADD COLUMN scheduled_for INTEGER',
            );
            db.execute('PRAGMA user_version=3');
            db.execute('COMMIT');
          } catch (_) {
            db.execute('ROLLBACK');
            rethrow;
          }
        }
      }
      if (db.userVersion != 3) {
        throw StateError('Unsupported cloud backup schema');
      }
      return CloudBackupWorkStore._(db, artifactDirectory);
    } catch (_) {
      db.close();
      rethrow;
    }
  }

  void close() => _db.close();

  Future<CloudBackupWorkRecord> stage(
    VerifiedBackupArtifact artifact, {
    required String providerId,
    required DateTime now,
    DateTime? scheduledFor,
  }) async {
    _validateRoute(providerId);
    final existing = byId(artifact.backupId);
    if (existing != null) {
      _requireSame(existing, artifact, providerId, scheduledFor);
      await _verifyFile(existing);
      return existing;
    }
    final fileName = '${artifact.backupId}.envelope';
    final target = File(
      '${artifactDirectory.path}${Platform.pathSeparator}$fileName',
    );
    await _writeImmutable(target, artifact);
    final timestamp = now.toUtc().millisecondsSinceEpoch;
    try {
      _db.execute(
        '''
        INSERT INTO backup_work(
          backup_id,provider_id,sha256,byte_length,created_at,scheduled_for,
          file_name,state,updated_at
        ) VALUES(?,?,?,?,?,?,?,'staged',?)
        ''',
        [
          artifact.backupId,
          providerId,
          artifact.sha256,
          artifact.byteLength,
          artifact.createdAt.millisecondsSinceEpoch,
          scheduledFor?.toUtc().millisecondsSinceEpoch,
          fileName,
          timestamp,
        ],
      );
    } catch (_) {
      final raced = byId(artifact.backupId);
      if (raced == null) rethrow;
      _requireSame(raced, artifact, providerId, scheduledFor);
    }
    return byId(artifact.backupId)!;
  }

  CloudBackupWorkRecord? byId(String backupId) {
    final rows = _db.select('SELECT * FROM backup_work WHERE backup_id=?', [
      backupId,
    ]);
    return rows.isEmpty ? null : _record(rows.single);
  }

  CloudBackupWorkRecord? latest({
    required String providerId,
    CloudBackupWorkState? state,
  }) {
    final rows = _db.select(
      state == null
          ? 'SELECT * FROM backup_work WHERE provider_id=? ORDER BY created_at DESC,backup_id DESC LIMIT 1'
          : 'SELECT * FROM backup_work WHERE provider_id=? AND state=? ORDER BY updated_at DESC,backup_id DESC LIMIT 1',
      state == null ? [providerId] : [providerId, state.name],
    );
    return rows.isEmpty ? null : _record(rows.single);
  }

  List<String> pendingBackupIds({String? providerId}) => _db
      .select(
        providerId == null
            ? "SELECT backup_id FROM backup_work WHERE state='staged' ORDER BY created_at,backup_id"
            : "SELECT backup_id FROM backup_work WHERE state='staged' AND provider_id=? ORDER BY created_at,backup_id",
        providerId == null ? const [] : [providerId],
      )
      .map((row) => row['backup_id'] as String)
      .toList(growable: false);

  bool hasPending(String providerId) => _db.select(
    "SELECT 1 FROM backup_work WHERE state='staged' AND provider_id=? LIMIT 1",
    [providerId],
  ).isNotEmpty;

  Future<VerifiedBackupArtifact> load(String backupId) async {
    final record = byId(backupId);
    if (record == null) throw StateError('Unknown cloud backup work item');
    final file = _file(record.fileName);
    final envelope = await file.readAsString();
    return VerifiedBackupArtifact.fromStaged(
      backupId: record.backupId,
      envelope: envelope,
      sha256: record.sha256,
      byteLength: record.byteLength,
      createdAt: record.createdAt,
    );
  }

  void markUploaded({
    required String backupId,
    required RemoteBackupMetadata metadata,
    required DateTime now,
  }) {
    final record = byId(backupId);
    if (record == null ||
        record.providerId != metadata.providerId ||
        record.remoteObjectId != metadata.objectId ||
        record.sha256 != metadata.sha256 ||
        record.byteLength != metadata.byteLength ||
        record.createdAt != metadata.createdAt.toUtc()) {
      throw StateError('Cloud backup completion does not match staged work');
    }
    _db.execute(
      "UPDATE backup_work SET state='uploaded',last_failure=NULL,updated_at=? WHERE backup_id=?",
      [now.toUtc().millisecondsSinceEpoch, backupId],
    );
  }

  void recordFailure({
    required String backupId,
    required CloudBackupWorkFailure failure,
    required DateTime now,
  }) {
    if (byId(backupId) == null)
      throw StateError('Unknown cloud backup work item');
    _db.execute(
      'UPDATE backup_work SET last_failure=?,updated_at=? WHERE backup_id=?',
      [failure.name, now.toUtc().millisecondsSinceEpoch, backupId],
    );
  }

  void clearFailure(String backupId, DateTime now) {
    if (byId(backupId) == null)
      throw StateError('Unknown cloud backup work item');
    _db.execute(
      'UPDATE backup_work SET last_failure=NULL,updated_at=? WHERE backup_id=?',
      [now.toUtc().millisecondsSinceEpoch, backupId],
    );
  }

  @override
  Future<String?> objectIdFor(String backupId) async =>
      byId(backupId)?.remoteObjectId;

  @override
  Future<void> save({
    required String backupId,
    required String objectId,
  }) async {
    _validateRoute(objectId);
    final record = byId(backupId);
    if (record == null) throw StateError('Reserve only staged backup work');
    if (record.remoteObjectId != null && record.remoteObjectId != objectId) {
      throw StateError('Cloud backup reservation conflict');
    }
    _db.execute(
      'UPDATE backup_work SET remote_object_id=? WHERE backup_id=? AND remote_object_id IS NULL',
      [objectId, backupId],
    );
  }

  CloudBackupWorkRecord _record(Row row) => CloudBackupWorkRecord(
    backupId: row['backup_id'] as String,
    providerId: row['provider_id'] as String,
    sha256: row['sha256'] as String,
    byteLength: row['byte_length'] as int,
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      row['created_at'] as int,
      isUtc: true,
    ),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(
      row['updated_at'] as int,
      isUtc: true,
    ),
    scheduledFor: switch (row['scheduled_for']) {
      final int value => DateTime.fromMillisecondsSinceEpoch(
        value,
        isUtc: true,
      ),
      _ => null,
    },
    fileName: row['file_name'] as String,
    state: CloudBackupWorkState.values.byName(row['state'] as String),
    remoteObjectId: row['remote_object_id'] as String?,
    lastFailure: switch (row['last_failure']) {
      final String value => CloudBackupWorkFailure.values.byName(value),
      _ => null,
    },
  );

  File _file(String fileName) {
    if (!RegExp(r'^[a-zA-Z0-9._:-]+\.envelope$').hasMatch(fileName)) {
      throw StateError('Invalid cloud backup artifact name');
    }
    return File('${artifactDirectory.path}${Platform.pathSeparator}$fileName');
  }

  Future<void> _verifyFile(CloudBackupWorkRecord record) async {
    await load(record.backupId);
  }
}

final class CloudBackupJobRunner {
  const CloudBackupJobRunner({
    required this.jobs,
    required this.work,
    required this.provider,
    this.checkpoint,
  });

  final PersistentJobStore jobs;
  final CloudBackupWorkStore work;
  final CloudBackupProvider provider;
  final void Function(String point)? checkpoint;

  Future<void> schedule(
    VerifiedBackupArtifact artifact, {
    required DateTime now,
    DateTime? scheduledFor,
  }) async {
    await work.stage(
      artifact,
      providerId: provider.providerId,
      now: now,
      scheduledFor: scheduledFor,
    );
    jobs.enqueue(
      idempotencyKey: '$_jobPrefix${artifact.backupId}',
      kind: cloudBackupUploadJobKind,
      now: now,
    );
  }

  void reconcile(DateTime now) {
    for (final backupId in work.pendingBackupIds(
      providerId: provider.providerId,
    )) {
      jobs.enqueue(
        idempotencyKey: '$_jobPrefix$backupId',
        kind: cloudBackupUploadJobKind,
        now: now,
      );
    }
  }

  Future<bool> runNext(DateTime now) async {
    final lease = jobs.claim(
      kind: cloudBackupUploadJobKind,
      now: now,
      lease: const Duration(minutes: 5),
    );
    if (lease == null) return false;
    try {
      final backupId = _backupId(lease.job.idempotencyKey);
      final artifact = await work.load(backupId);
      final metadata = await CloudBackupCoordinator(provider).upload(artifact);
      checkpoint?.call('after-upload');
      work.markUploaded(backupId: backupId, metadata: metadata, now: now);
      checkpoint?.call('after-record');
      if (!jobs.succeed(lease, now)) {
        throw StateError('Cloud backup lease was lost');
      }
      return true;
    } on CloudBackupProviderException catch (error) {
      final backupId = _backupId(lease.job.idempotencyKey);
      final failure = CloudBackupWorkFailure.values.byName(error.failure.name);
      work.recordFailure(backupId: backupId, failure: failure, now: now);
      if (_requiresUserAction(error.failure)) {
        jobs.failTerminal(lease, now);
      } else {
        jobs.fail(lease, now);
      }
      rethrow;
    } on CloudBackupValidationException {
      final backupId = _backupId(lease.job.idempotencyKey);
      work.recordFailure(
        backupId: backupId,
        failure: CloudBackupWorkFailure.integrityRejected,
        now: now,
      );
      jobs.failTerminal(lease, now);
      rethrow;
    } catch (_) {
      final backupId = _backupId(lease.job.idempotencyKey);
      work.recordFailure(
        backupId: backupId,
        failure: CloudBackupWorkFailure.temporaryLocalFailure,
        now: now,
      );
      jobs.fail(lease, now);
      rethrow;
    }
  }

  bool retryAfterUserAction(String backupId, DateTime now) {
    final record = work.byId(backupId);
    if (record == null || record.state != CloudBackupWorkState.staged) {
      return false;
    }
    final retried = jobs.retryTerminal('$_jobPrefix$backupId', now);
    if (retried) work.clearFailure(backupId, now);
    return retried;
  }
}

bool _requiresUserAction(CloudBackupProviderFailure failure) =>
    switch (failure) {
      CloudBackupProviderFailure.authenticationRequired ||
      CloudBackupProviderFailure.permissionDenied ||
      CloudBackupProviderFailure.quotaExceeded => true,
      CloudBackupProviderFailure.throttled ||
      CloudBackupProviderFailure.unavailable ||
      CloudBackupProviderFailure.uncertainResult => false,
    };

String _backupId(String key) {
  if (!key.startsWith(_jobPrefix) || key.length == _jobPrefix.length) {
    throw StateError('Invalid cloud backup job reference');
  }
  return key.substring(_jobPrefix.length);
}

void _validateRoute(String value) {
  if (value.isEmpty ||
      value.length > 200 ||
      !RegExp(r'^[a-zA-Z0-9._:-]+$').hasMatch(value)) {
    throw ArgumentError.value(value, 'value');
  }
}

void _requireSame(
  CloudBackupWorkRecord record,
  VerifiedBackupArtifact artifact,
  String providerId,
  DateTime? scheduledFor,
) {
  if (record.providerId != providerId ||
      record.sha256 != artifact.sha256 ||
      record.byteLength != artifact.byteLength ||
      record.createdAt != artifact.createdAt ||
      record.scheduledFor != scheduledFor?.toUtc()) {
    throw StateError('Backup ID belongs to different cloud backup work');
  }
}

Future<void> _writeImmutable(
  File target,
  VerifiedBackupArtifact artifact,
) async {
  if (await target.exists()) {
    final existing = await target.readAsString();
    await VerifiedBackupArtifact.fromStaged(
      backupId: artifact.backupId,
      envelope: existing,
      sha256: artifact.sha256,
      byteLength: artifact.byteLength,
      createdAt: artifact.createdAt,
    );
    if (existing != artifact.envelope) {
      throw StateError('Immutable backup file conflict');
    }
    return;
  }
  final temporary = File(
    '${target.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
  );
  try {
    await temporary.writeAsString(artifact.envelope, flush: true);
    await temporary.rename(target.path);
  } on FileSystemException {
    if (!await target.exists() ||
        await target.readAsString() != artifact.envelope) {
      rethrow;
    }
  } finally {
    if (await temporary.exists()) await temporary.delete();
  }
}
