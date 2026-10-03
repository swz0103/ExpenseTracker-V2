import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:storage_sqlcipher/storage_sqlcipher.dart';

import 'drive_client.dart';

/// Upload queue tables. Released migration steps are never edited.
final cloudSchema = SchemaModule('cloud', [
  [
    '''
    CREATE TABLE cloud_uploads (
      backup_id TEXT PRIMARY KEY,
      principal TEXT NOT NULL,
      file_path TEXT NOT NULL,
      byte_length INTEGER NOT NULL CHECK (byte_length > 0),
      sha256 TEXT NOT NULL,
      created_at TEXT NOT NULL,
      state TEXT NOT NULL
        CHECK (state IN ('queued', 'uploaded', 'failed', 'abandoned')),
      drive_file_id TEXT,
      session_uri TEXT,
      attempts INTEGER NOT NULL DEFAULT 0,
      next_attempt_at TEXT,
      failure TEXT,
      updated_at TEXT NOT NULL
    )
    ''',
    'CREATE INDEX cloud_uploads_due ON cloud_uploads (state, created_at)',
  ],
]);

enum UploadState {
  /// Waiting for, or in the middle of, its upload.
  queued,

  /// On Drive and verified; the local copy is deleted.
  uploaded,

  /// Stopped and needs the user: see [CloudUpload.failure]. Never blocks
  /// newer backups (health check G8-03).
  failed,

  /// Given up by the user or replaced by a newer backup; the local copy is
  /// deleted.
  abandoned,
}

/// One backup file on its way to Drive.
final class CloudUpload {
  const CloudUpload({
    required this.backupId,
    required this.principal,
    required this.file,
    required this.byteLength,
    required this.sha256,
    required this.createdAt,
    required this.state,
    required this.attempts,
    required this.updatedAt,
    this.driveFileId,
    this.sessionUri,
    this.nextAttemptAt,
    this.failure,
  });

  final String backupId;

  /// The Google account the backup belongs to.
  final String principal;
  final File file;
  final int byteLength;

  /// Lower-case hex SHA-256 of the file, taken when it was queued.
  final String sha256;
  final DateTime createdAt;
  final UploadState state;
  final int attempts;
  final DateTime updatedAt;
  final String? driveFileId;
  final Uri? sessionUri;
  final DateTime? nextAttemptAt;

  /// Why the upload failed: a [DriveFailure] name, `local-artifact` or
  /// `remote-mismatch`.
  final String? failure;
}

enum UploadResult {
  /// Nothing is due.
  idle,
  uploaded,

  /// A temporary problem; the upload resumes after [UploadRun.retryAt].
  retryLater,

  /// The upload stopped; the user can retry or abandon it.
  failed,

  /// Drive refused a freshly refreshed token; ask the user to sign in.
  /// The upload stays queued and no attempt is counted.
  signInRequired,
}

final class UploadRun {
  const UploadRun(this.result, {this.backupId, this.retryAt, this.failure});

  final UploadResult result;
  final String? backupId;
  final DateTime? retryAt;
  final String? failure;
}

/// A durable queue of backup files for Drive.
///
/// Uploads are resumable: the session URI is stored, so an interrupted
/// upload, even across app restarts, continues from the bytes Drive
/// already holds (G8-11). A verified upload deletes its local copy
/// (G8-17). A failed or stuck upload never blocks newer backups (G8-03).
///
/// Writes go through [SqlCipherStore.write]; the app runs [runNext] and
/// the other writers through the same queue as ledger commands.
final class CloudUploadQueue {
  CloudUploadQueue(
    this._store, {
    this.chunkSize = 4 * quantum,
    this.maxAttempts = 20,
  }) {
    if (chunkSize <= 0 || chunkSize % quantum != 0) {
      throw ArgumentError.value(chunkSize, 'chunkSize', 'Not 256 KiB units.');
    }
  }

  /// Drive's resumable chunk unit.
  static const quantum = 256 * 1024;

  final SqlCipherStore _store;
  final int chunkSize;
  final int maxAttempts;
  bool _running = false;

  /// Queues [file] for upload. Older queued backups of the same account
  /// that have not started uploading are replaced, since the new backup
  /// holds everything they hold.
  Future<CloudUpload> enqueue({
    required String backupId,
    required String principal,
    required File file,
    required DateTime createdAt,
    required DateTime now,
  }) async {
    if (backupId.isEmpty || principal.isEmpty) {
      throw ArgumentError('Empty backup id or principal.');
    }
    final (int, String) measured;
    try {
      measured = await _digest(file);
    } on _Stop {
      throw ArgumentError.value(file.path, 'file', 'Unreadable.');
    }
    final (length, digest) = measured;
    if (length == 0) throw ArgumentError.value(file.path, 'file', 'Empty.');
    final replaced = await _store.write((t) async {
      final rows = t.select(
        "SELECT file_path FROM cloud_uploads WHERE state = 'queued' "
        'AND principal = ? AND session_uri IS NULL',
        [principal],
      );
      t.execute(
        "UPDATE cloud_uploads SET state = 'abandoned', updated_at = ? "
        "WHERE state = 'queued' AND principal = ? AND session_uri IS NULL",
        [_time(now), principal],
      );
      t.execute(
        'INSERT INTO cloud_uploads (backup_id, principal, file_path, '
        'byte_length, sha256, created_at, state, updated_at) '
        "VALUES (?, ?, ?, ?, ?, ?, 'queued', ?)",
        [
          backupId,
          principal,
          file.path,
          length,
          digest,
          _time(createdAt),
          _time(now),
        ],
      );
      return [for (final row in rows) row['file_path']! as String];
    });
    for (final path in replaced) {
      await _delete(File(path));
    }
    return get(backupId)!;
  }

  CloudUpload? get(String backupId) {
    final rows = _store.select(
      'SELECT * FROM cloud_uploads WHERE backup_id = ?',
      [backupId],
    );
    return rows.isEmpty ? null : _upload(rows.single);
  }

  /// Uploads, oldest first, optionally in one [state].
  List<CloudUpload> uploads({UploadState? state}) {
    final rows = state == null
        ? _store.select('SELECT * FROM cloud_uploads ORDER BY created_at')
        : _store.select(
            'SELECT * FROM cloud_uploads WHERE state = ? ORDER BY created_at',
            [state.name],
          );
    return [for (final row in rows) _upload(row)];
  }

  /// When the newest backup that reached Drive was taken, so the app can
  /// warn when backups stop arriving.
  DateTime? lastUploaded(String principal) {
    final rows = _store.select(
      'SELECT MAX(created_at) AS at FROM cloud_uploads '
      "WHERE state = 'uploaded' AND principal = ?",
      [principal],
    );
    final at = rows.single['at'];
    return at == null ? null : DateTime.parse(at as String);
  }

  /// Gives up on an upload that has not finished and deletes its file.
  Future<void> abandon(String backupId, DateTime now) async {
    final path = await _store.write((t) async {
      final rows = t.select(
        'SELECT file_path FROM cloud_uploads WHERE backup_id = ? '
        "AND state IN ('queued', 'failed')",
        [backupId],
      );
      if (rows.isEmpty) return null;
      t.execute(
        "UPDATE cloud_uploads SET state = 'abandoned', session_uri = NULL, "
        'updated_at = ? WHERE backup_id = ?',
        [_time(now), backupId],
      );
      return rows.single['file_path']! as String;
    });
    if (path != null) await _delete(File(path));
  }

  /// Queues a failed upload again, with a fresh attempt budget.
  Future<void> retry(String backupId, DateTime now) async {
    await _store.write((t) async {
      t.execute(
        "UPDATE cloud_uploads SET state = 'queued', attempts = 0, "
        'next_attempt_at = NULL, failure = NULL, updated_at = ? '
        "WHERE backup_id = ? AND state = 'failed'",
        [_time(now), backupId],
      );
    });
  }

  /// Deletes local files left behind by finished uploads, for example
  /// after a crash between the upload and the delete. Returns the count.
  Future<int> sweep() async {
    var deleted = 0;
    for (final state in [UploadState.uploaded, UploadState.abandoned]) {
      for (final upload in uploads(state: state)) {
        if (await _delete(upload.file)) deleted++;
      }
    }
    return deleted;
  }

  /// Uploads the oldest due backup of [principal], or resumes it.
  Future<UploadRun> runNext({
    required DriveClient drive,
    required String principal,
    required DateTime now,
  }) async {
    if (_running) return const UploadRun(UploadResult.idle);
    _running = true;
    try {
      final rows = _store.select(
        "SELECT * FROM cloud_uploads WHERE state = 'queued' AND principal = ? "
        'AND (next_attempt_at IS NULL OR next_attempt_at <= ?) '
        'ORDER BY created_at LIMIT 1',
        [principal, _time(now)],
      );
      if (rows.isEmpty) return const UploadRun(UploadResult.idle);
      return await _run(drive, _upload(rows.single), now);
    } finally {
      _running = false;
    }
  }

  Future<UploadRun> _run(
    DriveClient drive,
    CloudUpload upload,
    DateTime now,
  ) async {
    final id = upload.backupId;
    try {
      final file = await _send(drive, upload);
      await _finish(upload, file, now);
      return UploadRun(UploadResult.uploaded, backupId: id);
    } on _Stop catch (stop) {
      await _fail(id, stop.reason, now);
      return UploadRun(UploadResult.failed, backupId: id, failure: stop.reason);
    } on FileSystemException {
      await _fail(id, 'local-artifact', now);
      return UploadRun(
        UploadResult.failed,
        backupId: id,
        failure: 'local-artifact',
      );
    } on DriveException catch (e) {
      switch (e.failure) {
        case DriveFailure.authenticationRequired:
          return UploadRun(UploadResult.signInRequired, backupId: id);
        case DriveFailure.permissionDenied || DriveFailure.quotaExceeded:
          await _fail(id, e.failure.name, now);
          return UploadRun(
            UploadResult.failed,
            backupId: id,
            failure: e.failure.name,
          );
        case DriveFailure.throttled ||
            DriveFailure.unavailable ||
            DriveFailure.sessionExpired ||
            DriveFailure.uncertain:
          final attempts = upload.attempts + 1;
          if (attempts >= maxAttempts) {
            await _fail(id, e.failure.name, now);
            return UploadRun(
              UploadResult.failed,
              backupId: id,
              failure: e.failure.name,
            );
          }
          final at = now.add(_backoff(attempts));
          await _update(id, {
            'attempts': attempts,
            'next_attempt_at': _time(at),
            'failure': e.failure.name,
          }, now);
          return UploadRun(UploadResult.retryLater, backupId: id, retryAt: at);
      }
    }
  }

  Future<DriveFile> _send(DriveClient drive, CloudUpload upload) async {
    final (length, digest) = await _digest(upload.file);
    if (length != upload.byteLength || digest != upload.sha256) {
      throw const _Stop('local-artifact');
    }
    var fileId = upload.driveFileId;
    if (fileId == null) {
      fileId = await drive.generateId();
      await _update(upload.backupId, {'drive_file_id': fileId}, null);
    }
    var session = upload.sessionUri;
    var status = const UploadStatus(0);
    if (session != null) {
      try {
        status = await drive.uploadStatus(session, length);
      } on DriveException catch (e) {
        if (e.failure != DriveFailure.sessionExpired) rethrow;
        session = null;
        await _update(upload.backupId, {'session_uri': null}, null);
      }
    }
    if (session == null) {
      // A lost reply may hide a finished upload: the reserved id tells.
      final existing = await drive.file(fileId);
      if (existing != null) return _verify(upload, existing);
      session = await drive.startUpload(
        fileId: fileId,
        name: 'expense-tracker-${upload.backupId}.etb',
        length: length,
        appProperties: {
          'format': driveBackupFormat,
          'backupId': upload.backupId,
          'createdAt': _time(upload.createdAt),
          'sha256': upload.sha256,
        },
      );
      await _update(upload.backupId, {'session_uri': '$session'}, null);
    }
    final reader = await upload.file.open();
    try {
      var stalls = 0;
      while (!status.complete) {
        final offset = status.received;
        if (offset < 0 || offset > length) {
          throw const DriveException(DriveFailure.unavailable);
        }
        await reader.setPosition(offset);
        final bytes = await reader.read(min(chunkSize, length - offset));
        if (offset + bytes.length > length || bytes.isEmpty) {
          throw const _Stop('local-artifact');
        }
        try {
          status = await drive.putChunk(
            session,
            offset: offset,
            bytes: bytes,
            length: length,
          );
        } on DriveException catch (e) {
          if (e.failure != DriveFailure.uncertain) rethrow;
          // The chunk may have landed; ask Drive where to continue.
          status = await drive.uploadStatus(session, length);
        }
        stalls = status.received > offset ? 0 : stalls + 1;
        if (stalls >= 3) throw const DriveException(DriveFailure.unavailable);
      }
    } finally {
      await reader.close();
    }
    return _verify(upload, status.file!);
  }

  DriveFile _verify(CloudUpload upload, DriveFile file) {
    if (file.byteLength != upload.byteLength ||
        file.backupId != upload.backupId ||
        (file.sha256 != null && file.sha256 != upload.sha256)) {
      throw const _Stop('remote-mismatch');
    }
    return file;
  }

  Future<void> _finish(CloudUpload upload, DriveFile file, DateTime now) async {
    await _store.write((t) async {
      t.execute(
        "UPDATE cloud_uploads SET state = 'uploaded', drive_file_id = ?, "
        'session_uri = NULL, next_attempt_at = NULL, failure = NULL, '
        "updated_at = ? WHERE backup_id = ? AND state = 'queued'",
        [file.id, _time(now), upload.backupId],
      );
    });
    await _delete(upload.file);
  }

  Future<void> _fail(String backupId, String reason, DateTime now) async {
    await _store.write((t) async {
      t.execute(
        "UPDATE cloud_uploads SET state = 'failed', failure = ?, "
        "next_attempt_at = NULL, updated_at = ? WHERE backup_id = ? "
        "AND state = 'queued'",
        [reason, _time(now), backupId],
      );
    });
  }

  /// Updates columns of a still-queued upload; an abandoned one stays so.
  Future<void> _update(
    String backupId,
    Map<String, Object?> columns,
    DateTime? now,
  ) async {
    final names = [...columns.keys, if (now != null) 'updated_at'];
    final values = [...columns.values, if (now != null) _time(now)];
    await _store.write((t) async {
      t.execute(
        'UPDATE cloud_uploads SET ${names.map((n) => '$n = ?').join(', ')} '
        "WHERE backup_id = ? AND state = 'queued'",
        [...values, backupId],
      );
    });
  }

  static Duration _backoff(int attempts) {
    final minutes = min(1 << min(attempts - 1, 20), 6 * 60);
    return Duration(minutes: minutes);
  }

  static Future<(int, String)> _digest(File file) async {
    final sink = Sha256().newHashSink();
    var length = 0;
    try {
      await for (final chunk in file.openRead()) {
        length += chunk.length;
        sink.add(chunk);
      }
    } on FileSystemException {
      throw const _Stop('local-artifact');
    }
    sink.close();
    final hash = await sink.hash();
    final hex = [
      for (final byte in hash.bytes) byte.toRadixString(16).padLeft(2, '0'),
    ].join();
    return (length, hex);
  }

  static Future<bool> _delete(File file) async {
    try {
      if (!await file.exists()) return false;
      await file.delete();
      return true;
    } on FileSystemException {
      return false;
    }
  }

  static String _time(DateTime time) => time.toUtc().toIso8601String();

  static CloudUpload _upload(Map<String, Object?> row) {
    DateTime? time(String column) {
      final text = row[column] as String?;
      return text == null ? null : DateTime.parse(text);
    }

    final session = row['session_uri'] as String?;
    return CloudUpload(
      backupId: row['backup_id']! as String,
      principal: row['principal']! as String,
      file: File(row['file_path']! as String),
      byteLength: row['byte_length']! as int,
      sha256: row['sha256']! as String,
      createdAt: time('created_at')!,
      state: UploadState.values.byName(row['state']! as String),
      attempts: row['attempts']! as int,
      updatedAt: time('updated_at')!,
      driveFileId: row['drive_file_id'] as String?,
      sessionUri: session == null ? null : Uri.parse(session),
      nextAttemptAt: time('next_attempt_at'),
      failure: row['failure'] as String?,
    );
  }
}

/// A problem retrying cannot fix.
final class _Stop implements Exception {
  const _Stop(this.reason);

  final String reason;
}
