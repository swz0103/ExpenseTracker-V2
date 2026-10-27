import 'dart:io';

import 'package:core/foundation_values.dart';
import 'package:vault/ledger_backup.dart';
import 'package:vault/ledger_vault.dart';

import '../startup.dart';
import 'keeper.dart';

/// The keys and backups of the open encrypted ledger.
final class VaultKeeper implements Keeper {
  VaultKeeper(
    this._startup,
    this._vault, {
    Future<void> Function()? beforeLock,
    Future<bool> Function(String path, String name)? export,
    Future<String?> Function()? pick,
  }) : _beforeLock = beforeLock,
       _export = export ?? _toDownloads,
       _pick = pick;

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

  /// Where a file to hand over is written until the person has it. Kept
  /// out of Android's cloud backup (res/xml/data_extraction_rules.xml),
  /// and emptied at each start (leftovers.dart).
  Directory get _exports => Directory('${_startup.directory.path}/exports');

  @override
  Future<bool> exportBackup() async {
    // A backup taken out of the phone carries the receipt photos too; the
    // weekly ones on the phone stay small. It is written to [_exports], not
    // beside the weekly ones, so it never fills the cloud backup's quota.
    final file = await _write(_exports, withPhotos: true);
    try {
      return await _export(file.path, file.path.split(RegExp(r'[/\\]')).last);
    } finally {
      if (file.existsSync()) await file.delete();
    }
  }

  /// The ledger's revision: it changes with every change kept.
  int get revision => _vault.store.revision;

  /// The ledger's own id, the same in its backups and on another phone it
  /// is restored to.
  String get ledgerId => _vault.keys.keyring.id;

  /// Writes a backup with the receipt photos where files wait to be handed
  /// over, gives it to [use], then deletes it.
  Future<T> withBackup<T>(Future<T> Function(File file) use) async {
    final file = await _write(_exports, withPhotos: true);
    try {
      return await use(file);
    } finally {
      if (file.existsSync()) await file.delete();
    }
  }

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

  Directory get _folder => Directory('${_startup.directory.path}/backups');

  @override
  String get backupFolder => _folder.path;

  @override
  Future<String> backUp({bool withPhotos = false}) async {
    final file = await _write(_folder, withPhotos: withPhotos);
    return file.path;
  }

  /// Writes an encrypted backup into [folder], named by the time it was
  /// taken.
  Future<File> _write(Directory folder, {required bool withPhotos}) async {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp =
        '${now.year}${two(now.month)}${two(now.day)}'
        '-${two(now.hour)}${two(now.minute)}${two(now.second)}'
        '${now.millisecond.toString().padLeft(3, '0')}';
    await folder.create(recursive: true);
    final file = File('${folder.path}/記帳本-$stamp.etbk');
    await LedgerBackup.write(
      store: _vault.store,
      keys: _vault.keys,
      file: file,
      backupId: PublicId.generate().value,
      createdAt: now,
      files: withPhotos ? _receipts() : const {},
    );
    return file;
  }

  /// The backups in [backupFolder], newest first; their names carry the
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
        final age = DateTime.now().difference(header.createdAt);
        if (age < every || header.revision == _vault.store.revision) {
          return null;
        }
      } on Object {
        // An unreadable newest backup is replaced by a good one.
      }
    }
    final path = await backUp();
    for (final old in _backups().skip(keep)) {
      await old.delete();
    }
    return path;
  }

  @override
  bool get hasPassword => !_startup.passwordless;

  @override
  Future<void> setPassword(String next) async {
    await changePassword(await _startup.quickSecret(), next);
    await _startup.forgetQuickKey();
  }

  @override
  Future<void> changePassword(String current, String next) async {
    await _startup.codec.unlockWithPassword(_vault.keys.keyring, current);
    await _vault.updateKeys(await _vault.keys.changePassword(next));
  }

  @override
  Future<String> newRecoveryCode() async {
    final rotated = await _vault.keys.rotateRecovery();
    await _vault.updateKeys(rotated.unlocked);
    await _given.writeAsString('', flush: true);
    return rotated.recoveryCode;
  }

  @override
  bool get recoveryGiven => _given.existsSync();

  File get _given => File('${_startup.directory.path}/recovery-given');

  /// Locks once queued changes are kept, so nothing writes to a closed
  /// store.
  @override
  Future<void> lock() async {
    await _beforeLock?.call();
    _startup.lock();
  }
}
