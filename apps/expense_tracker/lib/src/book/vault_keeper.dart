import 'dart:io';

import 'package:foundation_values/foundation_values.dart';
import 'package:ledger_backup/ledger_backup.dart';
import 'package:ledger_vault/ledger_vault.dart';

import '../startup.dart';
import 'keeper.dart';
import 'vault_journal.dart';

/// The keys and backups of the open encrypted ledger.
final class VaultKeeper implements Keeper {
  VaultKeeper(
    this._startup,
    this._vault,
    this._journal, {
    Future<void> Function()? beforeLock,
    Future<bool> Function(String path, String name)? export,
  }) : _beforeLock = beforeLock,
       _export = export ?? _toDownloads;

  final Startup _startup;
  final OpenVault _vault;
  final VaultJournal _journal;

  /// Waits for what the screens still have to keep, such as the ledger's
  /// queued changes.
  final Future<void> Function()? _beforeLock;

  /// Hands a backup file to the person: the system's save dialog on a
  /// phone, the Downloads folder on a computer.
  final Future<bool> Function(String path, String name) _export;

  static Future<bool> _toDownloads(String path, String name) async {
    final home =
        Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
    if (home == null) return false;
    final downloads = Directory('$home/Downloads');
    await downloads.create(recursive: true);
    await File(path).copy('${downloads.path}/$name');
    return true;
  }

  @override
  Future<bool> exportBackup() async {
    final path = await backUp();
    return _export(path, path.split(RegExp(r'[/\\]')).last);
  }

  @override
  Future<bool> exportFile(String name, String text) async {
    // Written beside the ledger only until it is handed over.
    final folder = Directory('${_startup.directory.path}/exports');
    await folder.create(recursive: true);
    final file = File('${folder.path}/$name');
    await file.writeAsString(text, flush: true);
    try {
      return await _export(file.path, name);
    } finally {
      await file.delete();
    }
  }

  Directory get _folder => Directory('${_startup.directory.path}/backups');

  @override
  String get backupFolder => _folder.path;

  @override
  Future<String> backUp() async {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp =
        '${now.year}${two(now.month)}${two(now.day)}'
        '-${two(now.hour)}${two(now.minute)}${two(now.second)}'
        '${now.millisecond.toString().padLeft(3, '0')}';
    await _folder.create(recursive: true);
    final file = File('${_folder.path}/記帳本-$stamp.etbk');
    await _journal.exclusive(
      () => LedgerBackup.write(
        store: _vault.store,
        keys: _vault.keys,
        file: file,
        backupId: PublicId.generate(),
        createdAt: UtcInstant(now),
      ),
    );
    return file.path;
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
        final age = DateTime.now().difference(header.createdAt.value);
        if (age < every || header.events == _vault.store.eventCount) {
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
    return rotated.recoveryCode;
  }

  /// Locks once queued changes, a running backup and any other job on
  /// the ledger are done, so nothing writes to a closed store.
  @override
  Future<void> lock() async {
    await _beforeLock?.call();
    await _journal.exclusive(() async {});
    _startup.lock();
  }
}
