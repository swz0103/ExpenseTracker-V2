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
