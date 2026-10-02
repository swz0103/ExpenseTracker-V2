import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:encrypted_storage_probe/encrypted_database.dart';
import 'package:sqlite3/sqlite3.dart';

import 'cloud_backup.dart';
import 'cloud_backup_work.dart';

final class CloudBackupScheduleRecord {
  const CloudBackupScheduleRecord({
    required this.providerId,
    required this.enabled,
    required this.interval,
    required this.nextDueAt,
  });

  final String providerId;
  final bool enabled;
  final Duration interval;
  final DateTime nextDueAt;
}

final class CloudBackupOccurrence {
  const CloudBackupOccurrence({
    required this.providerId,
    required this.dueAt,
    required this.backupId,
  });

  final String providerId;
  final DateTime dueAt;
  final String backupId;
}

final class CloudBackupScheduleStore {
  CloudBackupScheduleStore._(this._db);

  final Database _db;

  static CloudBackupScheduleStore open(File file, StorageKey key) {
    if (FileSystemEntity.typeSync(file.parent.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw StateError('Schedule database parent must be a directory');
    }
    final db = sqlite3.open(file.path);
    try {
      configureEncryption(db, key);
      db.execute('PRAGMA journal_mode=DELETE');
      db.execute('PRAGMA synchronous=FULL');
      if (db.userVersion == 0) {
        final existing = db.select(
          "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
        );
        if (existing.isNotEmpty)
          throw StateError('Unknown backup schedule schema');
        db.execute('''
          CREATE TABLE backup_schedules (
            provider_id TEXT PRIMARY KEY,
            enabled INTEGER NOT NULL CHECK(enabled IN (0,1)),
            interval_ms INTEGER NOT NULL CHECK(interval_ms BETWEEN 3600000 AND 31536000000),
            next_due_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          ) STRICT
        ''');
        db.execute('PRAGMA user_version=1');
      } else if (db.userVersion != 1) {
        throw StateError('Unsupported backup schedule schema');
      }
      return CloudBackupScheduleStore._(db);
    } catch (_) {
      db.close();
      rethrow;
    }
  }

  void close() => _db.close();

  void configure({
    required String providerId,
    required bool enabled,
    required Duration interval,
    required DateTime firstDueAt,
    required DateTime now,
  }) {
    _validateProviderId(providerId);
    if (interval < const Duration(hours: 1) ||
        interval > const Duration(days: 365)) {
      throw ArgumentError.value(interval, 'interval');
    }
    _db.execute(
      '''
      INSERT INTO backup_schedules(
        provider_id,enabled,interval_ms,next_due_at,updated_at
      ) VALUES(?,?,?,?,?)
      ON CONFLICT(provider_id) DO UPDATE SET
        enabled=excluded.enabled, interval_ms=excluded.interval_ms,
        next_due_at=excluded.next_due_at, updated_at=excluded.updated_at
      ''',
      [
        providerId,
        enabled ? 1 : 0,
        interval.inMilliseconds,
        firstDueAt.toUtc().millisecondsSinceEpoch,
        now.toUtc().millisecondsSinceEpoch,
      ],
    );
  }

  CloudBackupScheduleRecord? byProvider(String providerId) {
    final rows = _db.select(
      'SELECT * FROM backup_schedules WHERE provider_id=?',
      [providerId],
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    return CloudBackupScheduleRecord(
      providerId: row['provider_id'] as String,
      enabled: row['enabled'] == 1,
      interval: Duration(milliseconds: row['interval_ms'] as int),
      nextDueAt: DateTime.fromMillisecondsSinceEpoch(
        row['next_due_at'] as int,
        isUtc: true,
      ),
    );
  }

  Future<List<CloudBackupOccurrence>> due(DateTime now) async {
    final rows = _db.select(
      '''
      SELECT provider_id,next_due_at FROM backup_schedules
      WHERE enabled=1 AND next_due_at<=? ORDER BY next_due_at,provider_id
      ''',
      [now.toUtc().millisecondsSinceEpoch],
    );
    final result = <CloudBackupOccurrence>[];
    for (final row in rows) {
      final providerId = row['provider_id'] as String;
      final dueAt = DateTime.fromMillisecondsSinceEpoch(
        row['next_due_at'] as int,
        isUtc: true,
      );
      result.add(
        CloudBackupOccurrence(
          providerId: providerId,
          dueAt: dueAt,
          backupId: await _automaticBackupId(providerId, dueAt),
        ),
      );
    }
    return result;
  }

  bool acknowledge(CloudBackupOccurrence occurrence, DateTime now) {
    final current = byProvider(occurrence.providerId);
    if (current == null ||
        !current.enabled ||
        current.nextDueAt != occurrence.dueAt.toUtc()) {
      return false;
    }
    final elapsed =
        now.toUtc().millisecondsSinceEpoch -
        occurrence.dueAt.millisecondsSinceEpoch;
    final steps = elapsed < 0
        ? 1
        : (elapsed ~/ current.interval.inMilliseconds) + 1;
    final next = occurrence.dueAt.add(current.interval * steps);
    _db.execute(
      '''
      UPDATE backup_schedules SET next_due_at=?,updated_at=?
      WHERE provider_id=? AND enabled=1 AND next_due_at=?
      ''',
      [
        next.millisecondsSinceEpoch,
        now.toUtc().millisecondsSinceEpoch,
        occurrence.providerId,
        occurrence.dueAt.millisecondsSinceEpoch,
      ],
    );
    return _db.updatedRows == 1;
  }
}

typedef AutomaticBackupSource = Future<VerifiedBackupArtifact> Function(
  String providerId,
  String backupId,
  DateTime scheduledFor,
  DateTime capturedAt,
);

final class CloudBackupAutomaticScheduler {
  const CloudBackupAutomaticScheduler({
    required this.schedules,
    required this.runners,
    required this.source,
    this.checkpoint,
  });

  final CloudBackupScheduleStore schedules;
  final Map<String, CloudBackupJobRunner> runners;
  final AutomaticBackupSource source;
  final void Function(String point)? checkpoint;

  Future<int> tick(DateTime now) async {
    var scheduled = 0;
    for (final occurrence in await schedules.due(now)) {
      final runner = runners[occurrence.providerId];
      if (runner == null) continue;
      final existing = runner.work.byId(occurrence.backupId);
      if (existing != null) {
        runner.reconcile(now);
      } else {
        if (runner.work.hasPending(occurrence.providerId)) continue;
        final artifact = await source(
          occurrence.providerId,
          occurrence.backupId,
          occurrence.dueAt,
          now.toUtc(),
        );
        if (artifact.backupId != occurrence.backupId) {
          throw StateError(
            'Automatic backup source changed occurrence identity',
          );
        }
        await runner.schedule(
          artifact,
          now: now,
          scheduledFor: occurrence.dueAt,
        );
      }
      checkpoint?.call('after-schedule');
      if (!schedules.acknowledge(occurrence, now)) {
        throw StateError('Automatic backup schedule changed during execution');
      }
      scheduled++;
    }
    return scheduled;
  }
}

Future<String> _automaticBackupId(String providerId, DateTime dueAt) async {
  final digest = await Sha256().hash(
    utf8.encode('$providerId\n${dueAt.toUtc().toIso8601String()}'),
  );
  final hex = digest.bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return 'auto-$hex';
}

void _validateProviderId(String value) {
  if (value.isEmpty ||
      value.length > 200 ||
      !RegExp(r'^[a-zA-Z0-9._:-]+$').hasMatch(value)) {
    throw ArgumentError.value(value, 'providerId');
  }
}
