import 'dart:io';

import 'package:backup_security/backup_security.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger_sqlcipher/ledger_sqlcipher.dart';
import 'package:storage_sqlcipher/storage_sqlcipher.dart';

enum VaultProblem {
  /// [LedgerVault.create] found a ledger already on this device.
  alreadyExists,

  /// No ledger on this device yet.
  missing,

  /// The keyring file cannot be read.
  damagedKeyring,

  /// A keyring for another ledger was offered.
  otherLedger,
}

final class VaultException implements Exception {
  const VaultException(this.problem);

  final VaultProblem problem;

  @override
  String toString() => 'VaultException(${problem.name})';
}

/// An unlocked ledger: its keys and its open database.
final class OpenVault {
  OpenVault._(this._vault, this._keys, this.store)
    : ledger = LedgerStore(store);

  final LedgerVault _vault;
  UnlockedKeyring _keys;
  final SqlCipherStore store;
  final LedgerStore ledger;
  WorkspaceId? _fresh;

  /// The workspace of the ledger's first event, or a new one for an empty
  /// ledger; it becomes permanent with the first command.
  WorkspaceId get workspace {
    final first = store.journal(limit: 1);
    if (first.isNotEmpty) return first.single.workspace;
    return _fresh ??= WorkspaceId(PublicId.generate());
  }

  UnlockedKeyring get keys => _keys;

  /// Stores a changed keyring, such as a new password or device, and uses
  /// it from now on.
  Future<void> updateKeys(UnlockedKeyring keys) async {
    await _vault.save(keys);
    _keys = keys;
  }

  void close() => store.close();
}

/// The ledger's files on this device: `keyring.json` next to `ledger.db`.
///
/// The keyring holds the database key wrapped by the password, the
/// recovery code and any device keys, so the database opens even if the
/// device key is lost (health check G8-13), and nothing secret is kept in
/// plain form (G8-01). The keyring file is replaced atomically.
final class LedgerVault {
  LedgerVault(this.directory, {required this.codec, this.modules = const []});

  final Directory directory;
  final KeyringCodec codec;

  /// Schema modules opened with the ledger's, such as the upload queue.
  final List<SchemaModule> modules;

  File get keyringFile => File('${directory.path}/keyring.json');
  File get databaseFile => File('${directory.path}/ledger.db');
  File get _pending => File('${directory.path}/keyring.json.new');

  /// A ledger is here: its keyring, or a complete replacement that a
  /// crash left before the rename. A half-written first keyring is not a
  /// ledger, so setup can start again.
  bool get exists => keyringFile.existsSync() || _completePending();

  bool _completePending() {
    if (!_pending.existsSync()) return false;
    try {
      Keyring.parse(_pending.readAsStringSync());
      return true;
    } on KeyringException {
      return false;
    } on FormatException {
      return false;
    }
  }

  /// First launch. Returns the vault and the recovery code, which is shown
  /// once and never stored.
  Future<(OpenVault, String)> create(String password) async {
    _requireAbsent();
    final created = await codec.create(password);
    return (await adopt(created.unlocked), created.recoveryCode);
  }

  /// A new device restoring a backup: the keyring comes from the backup
  /// header, already unlocked with the password or recovery code.
  Future<OpenVault> adopt(UnlockedKeyring keys) async {
    _requireAbsent();
    await directory.create(recursive: true);
    if (await databaseFile.exists()) await databaseFile.delete();
    await _write(keys.keyring);
    return _open(keys);
  }

  Future<OpenVault> unlockWithPassword(String password) async {
    final keyring = await _keyring();
    return _open(await codec.unlockWithPassword(keyring, password));
  }

  Future<OpenVault> unlockWithRecovery(String recoveryCode) async {
    final keyring = await _keyring();
    return _open(await codec.unlockWithRecovery(keyring, recoveryCode));
  }

  Future<OpenVault> unlockWithDevice(
    String deviceId,
    DeviceKeyWrapper wrapper,
  ) async {
    final keyring = await _keyring();
    return _open(await codec.unlockWithDevice(keyring, deviceId, wrapper));
  }

  /// Stores a changed keyring: a new password, recovery code, device or
  /// backup key. It must belong to this ledger.
  Future<void> save(UnlockedKeyring keys) async {
    final current = await _keyring();
    if (current.id != keys.keyring.id) {
      throw const VaultException(VaultProblem.otherLedger);
    }
    await _write(keys.keyring);
  }

  void _requireAbsent() {
    if (exists) throw const VaultException(VaultProblem.alreadyExists);
  }

  Future<Keyring> _keyring() async {
    if (!await keyringFile.exists()) {
      // A crash during the replace leaves only the new file behind.
      if (!_completePending()) {
        throw const VaultException(VaultProblem.missing);
      }
      await _pending.rename(keyringFile.path);
    }
    try {
      return Keyring.parse(await keyringFile.readAsString());
    } on KeyringException {
      throw const VaultException(VaultProblem.damagedKeyring);
    } on FormatException {
      throw const VaultException(VaultProblem.damagedKeyring);
    }
  }

  /// Writes the new file in full, then renames it over the old one, so a
  /// crash leaves either the old keyring or the new one, never half.
  Future<void> _write(Keyring keyring) async {
    await _pending.writeAsString(keyring.encode(), flush: true);
    await _pending.rename(keyringFile.path);
  }

  OpenVault _open(UnlockedKeyring keys) {
    final store = SqlCipherStore.open(
      databaseFile,
      StorageKey(keys.databaseKey),
      modules: [ledgerSchema, ...modules],
    );
    return OpenVault._(this, keys, store);
  }
}
