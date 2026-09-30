import 'dart:io';
import 'dart:math';

import 'package:encrypted_storage_probe/encrypted_database.dart';
import 'package:sqlite3/sqlite3.dart';

enum JobState { queued, running, succeeded, retryableFailure, terminalFailure }

final class JobRecord {
  const JobRecord({
    required this.id,
    required this.idempotencyKey,
    required this.kind,
    required this.state,
    required this.attempts,
    required this.maxAttempts,
    required this.availableAt,
  });

  final String id;
  final String idempotencyKey;
  final String kind;
  final JobState state;
  final int attempts;
  final int maxAttempts;
  final DateTime availableAt;
}

final class JobLease {
  const JobLease(this.job, this.token);
  final JobRecord job;
  final String token;
}

/// Stores only routing metadata. Financial data and provider tokens never enter
/// this queue; a handler resolves the job's immutable business reference.
///
/// This store is for independently requested work. Financial use cases needing
/// a commit-coupled side effect must enqueue through their own transaction.
final class PersistentJobStore {
  PersistentJobStore._(this._db);

  final Database _db;

  static PersistentJobStore open(File file, StorageKey key) {
    final type = FileSystemEntity.typeSync(file.path, followLinks: false);
    if (type != FileSystemEntityType.notFound &&
        type != FileSystemEntityType.file) {
      throw StateError('Job store path is not a regular file');
    }
    final parentType = FileSystemEntity.typeSync(
      file.parent.path,
      followLinks: false,
    );
    if (parentType != FileSystemEntityType.directory) {
      throw StateError('Job store parent must be a directory');
    }
    final db = sqlite3.open(file.path);
    try {
      configureEncryption(db, key);
      db.execute('PRAGMA journal_mode=DELETE');
      db.execute('PRAGMA synchronous=FULL');
      db.execute('PRAGMA busy_timeout=10000');
      if (db.userVersion == 0) {
        final existing = db.select(
          "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
        );
        if (existing.isNotEmpty) throw StateError('Unknown job store schema');
        db.execute('BEGIN IMMEDIATE');
        try {
          db.execute('''
            CREATE TABLE jobs (
              id TEXT PRIMARY KEY,
              idempotency_key TEXT NOT NULL UNIQUE,
              kind TEXT NOT NULL,
              state TEXT NOT NULL CHECK(state IN ('queued','running','succeeded','retryableFailure','terminalFailure')),
              attempts INTEGER NOT NULL CHECK(attempts >= 0),
              max_attempts INTEGER NOT NULL CHECK(max_attempts BETWEEN 1 AND 20),
              available_at INTEGER NOT NULL,
              lease_until INTEGER,
              lease_token TEXT,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL
            ) STRICT
          ''');
          db.execute('CREATE INDEX jobs_ready ON jobs(state, available_at)');
          db.execute('PRAGMA user_version=1');
          db.execute('COMMIT');
        } catch (_) {
          db.execute('ROLLBACK');
          rethrow;
        }
      } else if (db.userVersion != 1) {
        throw StateError('Unsupported job store version');
      }
      return PersistentJobStore._(db);
    } catch (_) {
      db.close();
      rethrow;
    }
  }

  void close() => _db.close();

  JobRecord enqueue({
    required String idempotencyKey,
    required String kind,
    required DateTime now,
    int maxAttempts = 5,
  }) {
    _validateKey(idempotencyKey);
    _validateKey(kind);
    if (maxAttempts < 1 || maxAttempts > 20) {
      throw ArgumentError.value(maxAttempts, 'maxAttempts');
    }
    return _transaction(() {
      final existing = _byKey(idempotencyKey);
      if (existing != null) {
        if (existing.kind != kind || existing.maxAttempts != maxAttempts) {
          throw StateError('Idempotency key already belongs to another job');
        }
        return existing;
      }
      final id = _randomToken();
      final timestamp = now.toUtc().millisecondsSinceEpoch;
      _db.execute(
        '''
        INSERT INTO jobs(id,idempotency_key,kind,state,attempts,max_attempts,
                         available_at,created_at,updated_at)
        VALUES(?,?,?,'queued',0,?,?,?,?)
      ''',
        [
          id,
          idempotencyKey,
          kind,
          maxAttempts,
          timestamp,
          timestamp,
          timestamp,
        ],
      );
      return _byKey(idempotencyKey)!;
    });
  }

  JobRecord? byKey(String idempotencyKey) => _byKey(idempotencyKey);

  /// Claims at most one due job. Expired leases may be claimed again, so the
  /// consumer must make its external effect idempotent using job.id.
  JobLease? claim({
    required String kind,
    required DateTime now,
    required Duration lease,
  }) {
    _validateKey(kind);
    if (lease <= Duration.zero) throw ArgumentError.value(lease, 'lease');
    final timestamp = now.toUtc().millisecondsSinceEpoch;
    final until = timestamp + lease.inMilliseconds;
    if (until <= timestamp) throw ArgumentError.value(lease, 'lease');
    return _transaction(() {
      _db.execute(
        '''
        UPDATE jobs SET state='terminalFailure', lease_until=NULL,
          lease_token=NULL, updated_at=?
        WHERE state='running' AND lease_until<=? AND attempts>=max_attempts
      ''',
        [timestamp, timestamp],
      );
      final rows = _db.select(
        '''
        SELECT * FROM jobs
        WHERE kind=? AND (
          (state IN ('queued','retryableFailure') AND available_at<=?)
           OR (state='running' AND lease_until<=? AND attempts<max_attempts))
        ORDER BY available_at, created_at, id LIMIT 1
      ''',
        [kind, timestamp, timestamp],
      );
      if (rows.isEmpty) return null;
      final id = rows.single['id'] as String;
      final token = _randomToken();
      _db.execute(
        '''
        UPDATE jobs SET state='running', attempts=attempts+1,
          lease_until=?, lease_token=?, updated_at=? WHERE id=?
      ''',
        [until, token, timestamp, id],
      );
      return JobLease(_byId(id)!, token);
    });
  }

  /// A stale worker may never acknowledge or fail a newer lease.
  bool succeed(JobLease lease, DateTime now) => _finish(
    lease,
    now,
    (timestamp) => _db.execute(
      '''
      UPDATE jobs SET state='succeeded', lease_until=NULL, lease_token=NULL,
        updated_at=? WHERE id=? AND state='running' AND lease_token=?
    ''',
      [timestamp, lease.job.id, lease.token],
    ),
  );

  bool fail(
    JobLease lease,
    DateTime now, {
    Duration baseDelay = const Duration(seconds: 30),
    Duration maxDelay = const Duration(hours: 1),
  }) {
    if (baseDelay <= Duration.zero || maxDelay < baseDelay) {
      throw ArgumentError('Invalid retry delay');
    }
    return _finish(lease, now, (timestamp) {
      final current = _byId(lease.job.id)!;
      final terminal = current.attempts >= current.maxAttempts;
      final multiplier = 1 << min(current.attempts - 1, 19);
      final delay = min(
        baseDelay.inMilliseconds * multiplier,
        maxDelay.inMilliseconds,
      );
      _db.execute(
        '''
        UPDATE jobs SET state=?, available_at=?, lease_until=NULL,
          lease_token=NULL, updated_at=?
        WHERE id=? AND state='running' AND lease_token=?
      ''',
        [
          terminal ? 'terminalFailure' : 'retryableFailure',
          terminal ? timestamp : timestamp + delay,
          timestamp,
          lease.job.id,
          lease.token,
        ],
      );
    });
  }

  /// Stops retrying immediately for failures that require user action or can
  /// never succeed with the same immutable input.
  bool failTerminal(JobLease lease, DateTime now) => _finish(
    lease,
    now,
    (timestamp) => _db.execute(
      '''
      UPDATE jobs SET state='terminalFailure', available_at=?,
        lease_until=NULL, lease_token=NULL, updated_at=?
      WHERE id=? AND state='running' AND lease_token=?
    ''',
      [timestamp, timestamp, lease.job.id, lease.token],
    ),
  );

  /// Explicit manual retry retains the same id for remote deduplication.
  bool retryTerminal(String idempotencyKey, DateTime now) {
    _validateKey(idempotencyKey);
    return _transaction(() {
      final current = _byKey(idempotencyKey);
      if (current?.state != JobState.terminalFailure) return false;
      final timestamp = now.toUtc().millisecondsSinceEpoch;
      _db.execute(
        '''
        UPDATE jobs SET state='queued', attempts=0, available_at=?,
          lease_until=NULL, lease_token=NULL, updated_at=? WHERE id=?
      ''',
        [timestamp, timestamp, current!.id],
      );
      return true;
    });
  }

  bool _finish(JobLease lease, DateTime now, void Function(int) update) {
    return _transaction(() {
      final current = _db.select(
        "SELECT id FROM jobs WHERE id=? AND state='running' AND lease_token=?",
        [lease.job.id, lease.token],
      );
      if (current.isEmpty) return false;
      update(now.toUtc().millisecondsSinceEpoch);
      return true;
    });
  }

  JobRecord? _byKey(String key) {
    final rows = _db.select('SELECT * FROM jobs WHERE idempotency_key=?', [
      key,
    ]);
    return rows.isEmpty ? null : _record(rows.single);
  }

  JobRecord? _byId(String id) {
    final rows = _db.select('SELECT * FROM jobs WHERE id=?', [id]);
    return rows.isEmpty ? null : _record(rows.single);
  }

  JobRecord _record(Row row) => JobRecord(
    id: row['id'] as String,
    idempotencyKey: row['idempotency_key'] as String,
    kind: row['kind'] as String,
    state: JobState.values.byName(row['state'] as String),
    attempts: row['attempts'] as int,
    maxAttempts: row['max_attempts'] as int,
    availableAt: DateTime.fromMillisecondsSinceEpoch(
      row['available_at'] as int,
      isUtc: true,
    ),
  );

  T _transaction<T>(T Function() body) {
    _db.execute('BEGIN IMMEDIATE');
    try {
      final result = body();
      _db.execute('COMMIT');
      return result;
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }
}

void _validateKey(String value) {
  if (value.isEmpty ||
      value.length > 200 ||
      !RegExp(r'^[a-zA-Z0-9._:-]+$').hasMatch(value)) {
    throw ArgumentError.value(value, 'value');
  }
}

String _randomToken() {
  final random = Random.secure();
  return List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}
