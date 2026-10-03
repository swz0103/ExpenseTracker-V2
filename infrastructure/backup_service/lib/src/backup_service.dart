import 'dart:io';

import 'package:backup_security/backup_security.dart';
import 'package:drive_backup/drive_backup.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger_backup/ledger_backup.dart';
import 'package:ledger_sqlcipher/ledger_sqlcipher.dart';

/// What the backup screen shows: when the last copy reached Drive and
/// whether backups have stopped arriving (health check G8-03).
final class BackupHealth {
  const BackupHealth({
    required this.lastUploaded,
    required this.overdue,
    required this.pending,
    required this.failed,
  });

  /// When the newest backup on Drive was taken, if any.
  final DateTime? lastUploaded;

  /// No backup reached Drive within twice the schedule.
  final bool overdue;
  final int pending;
  final int failed;
}

final class SyncReport {
  const SyncReport(this.last, {required this.uploaded, required this.removed});

  /// The last upload run; anything but `idle` or `uploaded` needs a look.
  final UploadRun last;
  final int uploaded;

  /// Old backups moved to the Drive trash.
  final int removed;
}

/// Backups end to end, for one ledger and one Google account at a time.
///
/// A backup is the event journal written by [LedgerBackup] (no business
/// validation, so it always succeeds: G8-05), queued in [queue] and
/// uploaded later. The backup needs only the keyring's backup key, never
/// the password itself (G8-06).
final class BackupService {
  BackupService({
    required this.ledger,
    required this.queue,
    required this.staging,
    required this.exclusive,
  });

  final LedgerStore ledger;
  final CloudUploadQueue queue;

  /// Where backup files wait for upload; private app storage.
  final Directory staging;

  /// The same [Exclusive] the queue uses, such as `Bookkeeping.exclusive`.
  final Exclusive exclusive;

  /// Whether a scheduled backup is due: nothing queued or uploaded for
  /// [principal] within [every], and the ledger changed since the latest
  /// one (feature audit G-21).
  bool due({
    required String principal,
    required Duration every,
    required DateTime now,
  }) {
    DateTime? latest;
    var latestSeq = -1;
    for (final upload in queue.uploads()) {
      if (upload.principal != principal) continue;
      if (upload.state != UploadState.queued &&
          upload.state != UploadState.uploaded &&
          upload.state != UploadState.removed) {
        continue;
      }
      if (latest == null || upload.createdAt.isAfter(latest)) {
        latest = upload.createdAt;
        latestSeq = upload.lastSeq;
      }
    }
    if (latest == null) return true;
    return latestSeq != _lastSeq() && !now.isBefore(latest.add(every));
  }

  int _lastSeq() {
    final rows = ledger.store.select('SELECT max(seq) AS seq FROM events');
    return (rows.single['seq'] as int?) ?? 0;
  }

  /// Writes a backup now and queues it for upload.
  Future<CloudUpload> backupNow({
    required UnlockedKeyring keys,
    required String principal,
    required DateTime now,
  }) async {
    final backupId = PublicId.generate();
    await staging.create(recursive: true);
    final file = File('${staging.path}/${backupId.value}.etb');
    final BackupHeader header;
    try {
      header = await exclusive(
        () => LedgerBackup.write(
          store: ledger.store,
          keys: keys,
          file: file,
          backupId: backupId,
          createdAt: UtcInstant(now),
        ),
      );
    } on Object {
      if (await file.exists()) await file.delete();
      rethrow;
    }
    return queue.enqueue(
      backupId: backupId.value,
      principal: principal,
      file: file,
      createdAt: now,
      now: now,
      lastSeq: header.lastSeq,
    );
  }

  /// Uploads what is due, then trims Drive to [retention]. Pruning waits
  /// until nothing is left to upload, so a failing upload never costs an
  /// older good copy.
  Future<SyncReport> sync({
    required DriveClient drive,
    required String principal,
    required DateTime now,
    Retention retention = const Retention(),
  }) async {
    var uploaded = 0;
    var last = const UploadRun(UploadResult.idle);
    for (var i = 0; i < 20; i++) {
      last = await queue.runNext(drive: drive, principal: principal, now: now);
      if (last.result != UploadResult.uploaded) break;
      uploaded++;
    }
    var removed = 0;
    if (last.result == UploadResult.idle) {
      removed = await queue.prune(
        drive: drive,
        principal: principal,
        retention: retention,
        now: now,
      );
    }
    return SyncReport(last, uploaded: uploaded, removed: removed);
  }

  BackupHealth health({
    required String principal,
    required Duration every,
    required DateTime now,
  }) {
    final last = queue.lastUploaded(principal);
    var pending = 0;
    var failed = 0;
    for (final upload in queue.uploads()) {
      if (upload.principal != principal) continue;
      if (upload.state == UploadState.queued) pending++;
      if (upload.state == UploadState.failed) failed++;
    }
    return BackupHealth(
      lastUploaded: last,
      overdue: last == null || now.isAfter(last.add(every * 2)),
      pending: pending,
      failed: failed,
    );
  }

  /// Restores a backup file already on this device, for example one
  /// copied over by the user when Drive is unavailable. The file's own
  /// authenticated header identifies it.
  Future<BackupHeader> restoreFile({
    required File file,
    required Future<UnlockedKeyring> Function(Keyring keyring) unlock,
    required LedgerStore into,
  }) async {
    final header = await LedgerBackup.readHeader(file);
    final keys = await unlock(header.keyring);
    return LedgerBackup.restore(file: file, keys: keys, into: into);
  }

  /// Downloads [file] and restores it into the empty ledger [into].
  ///
  /// The backup id in the file's Drive properties must match the id in the
  /// backup header, which the restore authenticates; a file swapped for
  /// another genuine backup is refused (G8-07). [unlock] opens the keyring
  /// carried in the header, with the password or the recovery code.
  Future<BackupHeader> restore({
    required DriveClient drive,
    required DriveFile file,
    required Future<UnlockedKeyring> Function(Keyring keyring) unlock,
    required LedgerStore into,
  }) async {
    await staging.create(recursive: true);
    final local = File('${staging.path}/restore-${PublicId.generate().value}');
    try {
      await local.writeAsBytes(await drive.download(file.id), flush: true);
      final header = await LedgerBackup.readHeader(local);
      if (header.backupId.value != file.backupId) {
        throw const BackupException(
          BackupProblem.authenticationFailed,
          'backup id',
        );
      }
      final keys = await unlock(header.keyring);
      return await LedgerBackup.restore(file: local, keys: keys, into: into);
    } finally {
      if (await local.exists()) await local.delete();
    }
  }
}
