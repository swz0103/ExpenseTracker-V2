import 'package:app_core/app_core.dart';
import 'package:backup_security/backup_security.dart';
import 'package:flutter/foundation.dart';
import 'package:ledger_vault/ledger_vault.dart';

import 'session.dart';
import 'vault_session.dart';

/// A hardware key for unlocking without the password, such as an Android
/// Keystore key behind biometrics.
final class DeviceUnlock {
  const DeviceUnlock(this.id, this.wrapper);

  final String id;
  final DeviceKeyWrapper wrapper;
}

sealed class StartupState {
  const StartupState();
}

/// No ledger on this device: set a password, or restore a backup.
final class NeedsSetup extends StartupState {
  const NeedsSetup();
}

/// A ledger exists and is locked.
final class Locked extends StartupState {
  const Locked({required this.deviceUnlock});

  /// This device has a key to try before asking for the password. It is
  /// enrolled at the first password unlock; until then the device unlock
  /// fails with `KeyringError.unknownDevice`.
  final bool deviceUnlock;
}

/// Unlocked and ready.
final class Ready extends StartupState {
  const Ready(this.session, this.vault);

  final AppSession session;
  final OpenVault vault;
}

/// From app launch to an unlocked session. The screens only show the
/// [state] and call these methods; keys never leave this class and the
/// vault.
final class Startup extends ChangeNotifier {
  Startup(this._vault, {this.device, Clock? clock})
    : _clock = clock ?? SystemClock() {
    _state = _locked();
  }

  final LedgerVault _vault;
  final DeviceUnlock? device;
  final Clock _clock;
  late StartupState _state;

  StartupState get state => _state;

  /// Creates the ledger. Returns the recovery code, to show once.
  Future<String> setUp(String password) async {
    final (open, recovery) = await _vault.create(password);
    await _enrolDevice(open);
    _ready(open);
    return recovery;
  }

  Future<void> unlockWithPassword(String password) async {
    final open = await _vault.unlockWithPassword(password);
    await _enrolDevice(open);
    _ready(open);
  }

  Future<void> unlockWithRecovery(String recoveryCode) async {
    _ready(await _vault.unlockWithRecovery(recoveryCode));
  }

  Future<void> unlockWithDevice() async {
    final device = this.device;
    if (device == null) throw StateError('No device key.');
    _ready(await _vault.unlockWithDevice(device.id, device.wrapper));
  }

  /// Closes the database and forgets the session.
  void lock() {
    final state = _state;
    if (state is Ready) state.vault.close();
    _state = _locked();
    notifyListeners();
  }

  /// Adds this device's key once, after a password unlock.
  Future<void> _enrolDevice(OpenVault open) async {
    final device = this.device;
    if (device == null || open.keys.keyring.deviceIds.contains(device.id)) {
      return;
    }
    await open.updateKeys(await open.keys.addDevice(device.id, device.wrapper));
  }

  void _ready(OpenVault open) {
    _state = Ready(vaultSession(open, clock: _clock), open);
    notifyListeners();
  }

  StartupState _locked() {
    if (!_vault.exists) return const NeedsSetup();
    return Locked(deviceUnlock: device != null);
  }
}
