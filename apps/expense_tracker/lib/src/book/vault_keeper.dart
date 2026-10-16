import 'dart:io';

import 'package:foundation_values/foundation_values.dart';
import 'package:ledger_backup/ledger_backup.dart';
import 'package:ledger_vault/ledger_vault.dart';

import '../startup.dart';
import 'keeper.dart';
import 'vault_journal.dart';

/// The keys and backups of the open encrypted ledger.
final class VaultKeeper implements Keeper {
  VaultKeeper(this._startup, this._vault, this._journal);

  final Startup _startup;
  final OpenVault _vault;
  final VaultJournal _journal;

  Directory get _folder => Directory('${_startup.directory.path}/backups');

  @override
  String get backupFolder => _folder.path;

  @override
  Future<String> backUp() async {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp =
        '${now.year}${two(now.month)}${two(now.day)}'
        '-${two(now.hour)}${two(now.minute)}${two(now.second)}';
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

  @override
  void lock() => _startup.lock();
}
