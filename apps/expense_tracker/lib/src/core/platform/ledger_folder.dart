import 'dart:io';

import 'package:vault/ledger_backup.dart';

import '../diagnostics/error_log.dart';
import '../time/app_clock.dart';
import 'app_files.dart';

/// The files kept beside the ledger that say what became of it: the copy
/// Android's own backup takes, the ledgers kept before a restore, and the
/// marks of what the person was told. Read without the ledger's keys.
final class LedgerFolder {
  const LedgerFolder(this.directory);

  /// Where the ledger's files are kept.
  final Directory directory;

  /// Kept once this ledger's recovery code has been shown, so a backup
  /// leaving the phone does not make a new one (encrypted_backup_manager.dart).
  File get recoveryGiven => File('${directory.path}/recovery-given');

  /// The fingerprint of the rows a newer version wrote that the person was
  /// last told were set aside (quarantine_notices.dart): told once a set.
  File get quarantineTold => File('${directory.path}/quarantine-told');

  /// The copy of the ledger, without its photos, that Android's own
  /// backup takes to the person's Google account and brings back when the
  /// app is installed again or on a new phone (res/xml): the only file
  /// it takes.
  File get cloudCopy =>
      File('${directory.path}/${AppFiles.cloud}/${AppFiles.cloudCopy}');

  /// When [cloudCopy] was taken and how many records it holds; null when
  /// there is none, or it cannot be read (noted).
  Future<BackupHeader?> cloudCopyHeader() async {
    if (!cloudCopy.existsSync()) return null;
    try {
      return await LedgerBackup.readHeader(cloudCopy);
    } on Object catch (error) {
      ErrorLog.instance.record('讀取備份標頭', error);
      return null;
    }
  }

  /// A new ledger instead of the one brought back: that copy moves where
  /// the ledgers kept before a restore are, so the new ledger's copy does
  /// not replace it unseen.
  Future<void> setAsideCloudCopy() async {
    final copy = cloudCopy;
    if (!copy.existsSync()) return;
    await beforeRestore.create(recursive: true);
    await copy.rename(
      '${beforeRestore.path}/brought-back-'
      '${AppClock.now().millisecondsSinceEpoch}.etbk',
    );
  }

  /// Where the ledger is kept as it was before a restore from settings.
  Directory get beforeRestore => Directory('${directory.path}/before-restore');

  /// The ledgers kept before a restore from settings, newest first, to
  /// go back to one.
  List<File> keptBeforeRestore() {
    final folder = beforeRestore;
    if (!folder.existsSync()) return const [];
    return [
      for (final entity in folder.listSync())
        if (entity is File && entity.path.endsWith('.etbk')) entity,
    ]..sort((a, b) => b.path.compareTo(a.path));
  }

  /// The ledgers kept before a restore with what their backups say (null
  /// for one that cannot be read), the one taken last first: by when it
  /// was taken, not when the file was last written, which a copy Android
  /// brought back does not keep.
  Future<List<(File, BackupHeader?)>> keptLedgers() async {
    final kept = <(File, BackupHeader?)>[];
    for (final file in keptBeforeRestore()) {
      BackupHeader? header;
      try {
        header = await LedgerBackup.readHeader(file);
      } on Object catch (error) {
        ErrorLog.instance.record('讀取備份標頭', error);
      }
      kept.add((file, header));
    }
    final epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    return kept..sort(
      (a, b) => (b.$2?.createdAt ?? epoch).compareTo(a.$2?.createdAt ?? epoch),
    );
  }

  /// When the backup at [path] was taken and how many records it holds,
  /// read without opening it.
  Future<BackupHeader> peek(String path) => LedgerBackup.readHeader(File(path));
}
