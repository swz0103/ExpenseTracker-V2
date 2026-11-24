import 'dart:io';
import 'dart:math';

import 'package:core/foundation_values.dart';
import 'package:vault/ledger_backup.dart';
import 'package:vault/ledger_vault.dart';

import '../../../core/messages/key_failures.dart' as words;
import '../../../core/platform/startup.dart';
import 'backup_manager.dart';
import '../../../core/time/app_clock.dart';
import '../../../core/diagnostics/error_log.dart';
import '../../../core/diagnostics/error_steps.dart';

/// The keys and backups of the open encrypted ledger.
final class EncryptedBackupManager implements BackupManager {
  EncryptedBackupManager(
    this._startup,
    this._vault, {
    this._beforeLock,
    Future<bool> Function(String path, String name)? export,
    this._pick,
  }) : _export = export ?? _toDownloads;

  final Startup _startup;
  final OpenVault _vault;

  /// Waits for what the screens still have to keep, such as the ledger's
  /// queued changes.
  final Future<void> Function()? _beforeLock;

  /// Hands a backup file to the person: the system's save dialog on a
  /// phone, the Downloads folder on a computer.
  final Future<bool> Function(String path, String name) _export;

  /// Lets the person choose a file and returns the path of a copy: the
  /// system's file picker on a phone; none on a computer.
  final Future<String?> Function()? _pick;

  static Future<bool> _toDownloads(String path, String name) async {
    final home =
        Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
    if (home == null) return false;
    final downloads = Directory('$home/Downloads');
    await downloads.create(recursive: true);
    await File(path).copy('${downloads.path}/$name');
    return true;
  }

  /// The sealed receipt photos, by name, for a backup to carry.
  Map<String, File> _receipts() {
    final folder = Directory('${_startup.directory.path}/receipts');
    if (!folder.existsSync()) return const {};
    return {
      for (final entity in folder.listSync())
        if (entity is File) entity.uri.pathSegments.last: entity,
    };
  }

  /// Where a file to hand over is written until the person has it;
  /// emptied at each start (leftovers.dart).
  Directory get _exports => Directory('${_startup.directory.path}/exports');

  @override
  Future<bool> exportBackup() async {
    // A backup taken out of the phone carries the receipt photos too; the
    // weekly ones on the phone stay small. It is written to [_exports], not
    // beside the weekly ones, so it never fills the cloud backup's quota.
    final file = await _write(_exports, withPhotos: true);
    try {
      final saved = await _export(
        file.path,
        file.path.split(RegExp(r'[/\\]')).last,
      );
      if (saved) {
        await _exported.writeAsString(
          AppClock.now().toUtc().toIso8601String(),
          flush: true,
        );
      }
      return saved;
    } finally {
      if (file.existsSync()) await file.delete();
    }
  }

  /// Notes when a backup was last handed over by hand.
  File get _exported => File('${_startup.directory.path}/exported-at');

  @override
  DateTime? get exportedAt {
    final file = _exported;
    if (!file.existsSync()) return null;
    return DateTime.tryParse(file.readAsStringSync().trim())?.toLocal();
  }

  /// The ledger's revision: it changes with every change kept.
  int get revision => _vault.store.revision;

  /// The ledger's own id, the same in its backups and on another phone it
  /// is restored to.
  String get ledgerId => _vault.keys.keyring.id;

  /// The backup key epoch backups are sealed with now: raised by a reset
  /// of the keys (or a new backup key), so older ones can be told apart.
  int get backupEpoch => _vault.keys.currentBackupEpoch;

  /// Writes a backup with the receipt photos where files wait to be handed
  /// over, gives it to [use], then deletes it.
  Future<T> withBackup<T>(
    Future<T> Function(File file) use, {
    bool withPhotos = true,
  }) async {
    final file = await _write(_exports, withPhotos: withPhotos);
    try {
      return await use(file);
    } finally {
      if (file.existsSync()) await file.delete();
    }
  }

  /// Writes a backup, with the receipt photos unless told not to, into
  /// [folder] and leaves it there, for the background job to deliver
  /// (outbox.dart).
  Future<File> writeInto(Directory folder, {bool withPhotos = true}) =>
      _write(folder, withPhotos: withPhotos);

  @override
  Future<bool> exportFile(String name, String text) async {
    // Written beside the ledger only until it is handed over.
    final folder = _exports;
    await folder.create(recursive: true);
    final file = File('${folder.path}/$name');
    await file.writeAsString(text, flush: true);
    try {
      return await _export(file.path, name);
    } finally {
      if (file.existsSync()) await file.delete();
    }
  }

  @override
  Future<bool> exportBytes(String name, List<int> bytes) async {
    final folder = _exports;
    await folder.create(recursive: true);
    final file = File('${folder.path}/$name');
    await file.writeAsBytes(bytes, flush: true);
    try {
      return await _export(file.path, name);
    } finally {
      if (file.existsSync()) await file.delete();
    }
  }

  @override
  Future<String?> readFile() async {
    final path = await _pick?.call();
    if (path == null) return null;
    final file = File(path);
    try {
      return await file.readAsString();
    } finally {
      if (file.existsSync()) await file.delete();
    }
  }

  /// Where the weekly backups are kept.
  Directory get _folder => Directory('${_startup.directory.path}/backups');

  /// Writes an encrypted backup into the backups folder and returns its
  /// path.
  Future<String> backUp({bool withPhotos = false}) async {
    final file = await _write(_folder, withPhotos: withPhotos);
    return file.path;
  }

  /// What a backup's file name starts with, before the time it was taken.
  static const _backupName = '記帳本';

  /// The backups being written, one after another: two at once could take
  /// the same name in the same millisecond (F65).
  var _writing = Future<void>.value();

  /// Runs [work] once every backup asked for before it is written.
  Future<T> _oneAtATime<T>(Future<T> Function() work) {
    final run = _writing.then((_) => work());
    _writing = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  /// Writes an encrypted backup into [folder], named [name] and the time
  /// it was taken, once the backups asked for before are written.
  Future<File> _write(
    Directory folder, {
    required bool withPhotos,
    String name = _backupName,
  }) =>
      _oneAtATime(() => _writeNow(folder, withPhotos: withPhotos, name: name));

  /// [_write], to be called only while no other backup is written.
  Future<File> _writeNow(
    Directory folder, {
    required bool withPhotos,
    required String name,
  }) async {
    final now = AppClock.now();
    final two = twoDigits;
    final stamp =
        '${BusinessDate.of(now).compact}'
        '-${two(now.hour)}${two(now.minute)}${two(now.second)}'
        '${now.millisecond.toString().padLeft(3, '0')}';
    await folder.create(recursive: true);
    var file = File('${folder.path}/$name-$stamp.etbk');
    // Two written in the same millisecond, as the outbox may.
    for (var n = 2; file.existsSync(); n++) {
      file = File('${folder.path}/$name-$stamp-$n.etbk');
    }
    // Written beside and renamed once whole: a write cut short, as when
    // the phone stops the app, never looks like a backup, and so never
    // takes the place of one of the good ones kept. Its name is its own,
    // so no other write can take it away before the rename (F65).
    final part = File(
      '${file.path}.${Random.secure().nextInt(1 << 32).toRadixString(36)}'
      '.part',
    );
    // A large change being kept on a worker is waited for: the backup
    // reads the whole book in one read on a worker (readApart, D41), as
    // one state (DAT-03). Nothing waits between this and that read.
    final store = _vault.store;
    while (store.busyApart) {
      await store.idle;
    }
    try {
      await LedgerBackup.write(
        store: _vault.store,
        keys: _vault.keys,
        file: part,
        backupId: PublicId.generate().value,
        createdAt: now,
        files: withPhotos ? _receipts() : const {},
      );
      return await part.rename(file.path);
    } on Object {
      if (part.existsSync()) part.deleteSync();
      rethrow;
    }
  }

  /// Every backup the app keeps on the phone, the weekly ones and the
  /// copies kept before a restore or an upgrade, with the key epoch it
  /// was sealed with and when it was taken; one whose header cannot be
  /// read is left out, noted.
  Future<List<(File, int, DateTime)>> keptBackups() async {
    final kept = <(File, int, DateTime)>[];
    for (final file in [..._backups(), ..._startup.keptBeforeRestore()]) {
      try {
        final header = await LedgerBackup.readHeader(file);
        kept.add((file, header.backupEpoch, header.createdAt));
      } on Object catch (error, stack) {
        ErrorLog.instance.record(ErrorSteps.backupHeader, error, stack);
      }
    }
    return kept;
  }

  /// The databases kept beside the ledger (copies set aside as damaged,
  /// a ledger set aside in the old format), each with when it was last
  /// written: still encrypted with the keys they were made under.
  List<(File, DateTime)> keptDatabases() => [
    for (final file in _vault.keptDatabases())
      if (file.existsSync()) (file, file.lastModifiedSync()),
  ];

  /// Deletes [file], one of [keptDatabases], with its log.
  Future<void> deleteKeptDatabase(File file) => _vault.deleteKept(file);

  /// The backups in the backups folder, newest first; their names carry the
  /// time they were taken.
  List<File> _backups() {
    if (!_folder.existsSync()) return const [];
    return [
      for (final entity in _folder.listSync())
        if (entity is File && entity.path.endsWith('.etbk')) entity,
    ]..sort((a, b) => b.path.compareTo(a.path));
  }

  /// Writes a backup when the newest one is older than [every] and the
  /// ledger changed since, then keeps only the newest [keep]. Returns the
  /// new backup's path, or null when none was due.
  Future<String?> backUpIfDue({
    Duration every = const Duration(days: 7),
    int keep = 5,
  }) async {
    final files = _backups();
    if (files.isNotEmpty) {
      try {
        final header = await LedgerBackup.readHeader(files.first);
        final age = AppClock.now().difference(header.createdAt);
        if (age < every || header.revision == _vault.store.revision) {
          return null;
        }
      } on Object catch (error, stack) {
        // An unreadable newest backup is replaced by a good one.
        ErrorLog.instance.record(ErrorSteps.backupHeader, error, stack);
      }
    }
    final path = await backUp();
    for (final old in _backups().skip(keep)) {
      await old.delete();
    }
    return path;
  }

  /// Keeps [Startup.cloudCopy], the copy Android's own backup takes to
  /// the person's Google account, as the ledger now stands, without its
  /// photos (they go to Drive or a folder). Written again only when the
  /// ledger changed since. True when it was written. Asked for twice at
  /// once, the second waits for the first and finds the copy current
  /// (F65: the two had raced over one file).
  Future<bool> keepCloudCopy() => _oneAtATime(_keepCloudCopy);

  Future<bool> _keepCloudCopy() async {
    final target = _startup.cloudCopy;
    if (target.existsSync()) {
      try {
        final header = await LedgerBackup.readHeader(target);
        // The same revision sealed with keys since reset is written again:
        // the old keys must not stay in the person's Google account.
        if (header.revision == _vault.store.revision &&
            header.backupEpoch == backupEpoch) {
          return false;
        }
      } on Object catch (error, stack) {
        // Unreadable: written again.
        ErrorLog.instance.record(ErrorSteps.backupHeader, error, stack);
      }
    }
    // Written in exports/, not in cloud/: Android's backup takes all of
    // cloud/, so a write cut short there would go to the person's Google
    // account. Renamed over the last one in the same storage: Android
    // never takes half a file.
    final file = await _writeNow(
      _exports,
      withPhotos: false,
      name: _backupName,
    );
    await target.parent.create(recursive: true);
    await file.rename(target.path);
    return true;
  }

  @override
  DateTime? get cloudCopyAt {
    final copy = _startup.cloudCopy;
    return copy.existsSync() ? copy.lastModifiedSync() : null;
  }

  @override
  DateTime? get googleTakenAt {
    final file = File('${_startup.directory.path}/google-backup-taken');
    if (!file.existsSync()) return null;
    final ms = int.tryParse(file.readAsStringSync().trim());
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  @override
  bool get hasPassword => !_startup.passwordless;

  @override
  bool get canUseFingerprint => hasPassword && _startup.device != null;

  @override
  bool get fingerprintOn => _startup.deviceEnrolled;

  @override
  Future<bool> turnFingerprint({required bool on}) async {
    if (on) return _startup.enrolDevice();
    await _startup.removeDevice();
    return true;
  }

  @override
  bool get passwordBelowRule => hasPassword && _startup.passwordBelowRule;

  @override
  String get passwordRule => words.passwordRule;

  @override
  String? refusePassword(String password) => words.passwordRefusal(password);

  @override
  String get passphraseRule => words.passphraseRule;

  @override
  String? refusePassphrase(String passphrase) =>
      words.passphraseRefusal(passphrase);

  /// Runs [change], a refusal by the keys said in words ([KeyRefused]).
  static Future<T> _said<T>(Future<T> Function() change) async {
    try {
      return await change();
    } on Exception catch (error) {
      final said = words.keyRefusal(error);
      if (said == null) rethrow;
      throw KeyRefused(said);
    }
  }

  @override
  bool get hasBackupPassphrase => _vault.keys.keyring.hasPassphrase;

  @override
  Future<void> setBackupPassphrase(String passphrase) => _said(
    () async => _vault.updateKeys(await _vault.keys.setPassphrase(passphrase)),
  );

  @override
  Future<void> removeBackupPassphrase() =>
      _vault.updateKeys(_vault.keys.removePassphrase());

  /// Keeps what the screens still have to write, then replaces every key;
  /// the app opens the ledger afresh on the new ones and shows the new
  /// recovery code.
  @override
  Future<void> resetKeys(String? currentPassword) async {
    await _beforeLock?.call();
    await _said(() => _startup.resetKeys(password: currentPassword));
  }

  @override
  Future<void> setPassword(String next) async {
    await changePassword(await _startup.quickSecret(), next);
    await _startup.forgetQuickKey();
  }

  @override
  Future<void> changePassword(String current, String next) => _said(() async {
    await _startup.codec.unlockWithPassword(_vault.keys.keyring, current);
    await _vault.updateKeys(await _vault.keys.changePassword(next));
  });

  @override
  Future<String> newRecoveryCode() async {
    final rotated = await _vault.keys.rotateRecovery();
    await _vault.updateKeys(rotated.unlocked);
    await _given.writeAsString('', flush: true);
    return rotated.recoveryCode;
  }

  @override
  bool get recoveryGiven => _given.existsSync();

  File get _given => _startup.recoveryGiven;

  /// Locks once queued changes are kept and the backups being written
  /// have read what they need, so nothing writes to or reads from a
  /// closed store (ARC-04: the weekly backup did).
  @override
  Future<void> lock() async {
    await _beforeLock?.call();
    await _writing;
    _startup.lock();
  }

  /// Keeps the ledger as it was before a restore from settings, with its
  /// photos, apart from the weekly backups. The two taken last stay, by
  /// when their backups say they were taken (their names do not sort by
  /// time: a copy Android brought back is named `brought-back-…`), and
  /// that copy is never one of those let go; the lock screen offers them
  /// to restore, and compares the backup chosen with this one.
  @override
  Future<String> restoreAnother() async {
    await _beforeLock?.call();
    final folder = _startup.beforeRestore;
    final kept = await _write(folder, withPhotos: true);
    final header = await LedgerBackup.readHeader(kept);
    final older = [
      for (final (file, header) in await _startup.keptLedgers())
        if (!file.uri.pathSegments.last.startsWith('brought-back') &&
            !file.uri.pathSegments.last.startsWith(_beforeUpgrade))
          (file, header),
    ];
    // keptLedgers is newest first; one that cannot be read counts as the
    // oldest.
    for (final (old, _) in older.skip(2)) {
      await old.delete();
    }
    _startup.lockToRestore(header);
    return kept.path;
  }

  /// How the copies [keepBeforeUpgrade] keeps are named.
  static const _beforeUpgrade = 'before-upgrade';

  /// Keeps the ledger as it is, with its photos, where the ledgers kept
  /// before a restore are, before an earlier version's book is brought up
  /// to this one (book_migrations.dart): the lock screen offers it to
  /// restore. The two written last stay; these are apart from the copies
  /// kept before a restore and never let go for them.
  Future<File> keepBeforeUpgrade() async {
    final folder = _startup.beforeRestore;
    final kept = await _write(folder, withPhotos: true, name: _beforeUpgrade);
    // keptLedgers is newest first, by the time in each header; the one
    // just written stays whatever the times say.
    final copies = [
      kept,
      for (final (file, _) in await _startup.keptLedgers())
        if (file.uri.pathSegments.last.startsWith(_beforeUpgrade) &&
            file.path != kept.path)
          file,
    ];
    for (final old in copies.skip(2)) {
      await old.delete();
    }
    return kept;
  }
}
