import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:backup_security/backup_security.dart';
import 'package:flutter/foundation.dart';
import 'package:ledger_backup/ledger_backup.dart';
import 'package:ledger_vault/ledger_vault.dart';

/// A hardware key for unlocking without the password, such as an Android
/// Keystore key behind biometrics.
final class DeviceUnlock {
  const DeviceUnlock(this.id, this.wrapper, {this.hasKey});

  final String id;
  final DeviceKeyWrapper wrapper;

  /// Whether the hardware key is still there; Android drops it when a
  /// fingerprint is added or removed. Null when it cannot be lost.
  final Future<bool> Function()? hasKey;
}

sealed class StartupState {
  const StartupState();
}

/// No ledger on this device: start one, with or without a password, or
/// restore a backup.
final class NeedsSetup extends StartupState {
  const NeedsSetup();
}

/// A ledger exists and is locked.
final class Locked extends StartupState {
  const Locked({required this.deviceUnlock, this.askFirst = true});

  /// This device has a key to try before asking for the password. It is
  /// enrolled at the first password unlock; until then the device unlock
  /// fails with `KeyringError.unknownDevice`.
  final bool deviceUnlock;

  /// Whether to ask for the fingerprint as soon as the screen opens: not
  /// after the person turned enrolling it down.
  final bool askFirst;
}

/// Unlocked and ready.
final class Ready extends StartupState {
  const Ready(this.vault);

  final OpenVault vault;
}

/// From app launch to an unlocked session. The screens only show the
/// [state] and call these methods; keys never leave this class and the
/// vault.
final class Startup extends ChangeNotifier {
  Startup(this._vault, {this.device}) {
    _state = _locked();
  }

  final LedgerVault _vault;
  final DeviceUnlock? device;
  late StartupState _state;
  String? _recovery;

  StartupState get state => _state;

  /// Where the ledger's files are kept.
  Directory get directory => _vault.directory;

  /// Opens and checks the ledger's keys.
  KeyringCodec get codec => _vault.codec;

  /// Where the key of a ledger opened without a password is kept, in the
  /// app's private folder, until the person sets a password.
  File get _quickKey => File('${directory.path}/quick-open.key');

  /// Kept when the person turned the fingerprint down, so a password
  /// unlock stops asking; asking for the fingerprint drops it.
  File get _noDevice => File('${directory.path}/no-fingerprint');

  /// The ledger opens without asking: no password has been set.
  bool get passwordless => _quickKey.existsSync();

  /// Creates the ledger without asking for anything: a random key kept
  /// on this device opens it, and a password can be set later.
  Future<void> setUpWithoutPassword() async {
    await directory.create(recursive: true);
    final secret = _newSecret();
    await _quickKey.writeAsString(secret, flush: true);
    final (open, _) = await _vault.create(secret);
    _ready(open);
  }

  static String _newSecret() {
    final random = Random.secure();
    return base64Url.encode([for (var i = 0; i < 32; i++) random.nextInt(256)]);
  }

  /// After the recovery code opened [open], the ledger opens by itself
  /// from now on, as one without a password: the code is often all the
  /// person has, such as for a backup of a ledger that had no password.
  /// A password can be set again in settings.
  Future<OpenVault> _openWithoutPassword(OpenVault open) async {
    final secret = _newSecret();
    await open.updateKeys(await open.keys.changePassword(secret));
    await _quickKey.writeAsString(secret, flush: true);
    return open;
  }

  /// Opens a ledger set up without a password.
  Future<void> openQuietly() async {
    _ready(await _vault.unlockWithPassword(await quickSecret()));
  }

  /// The key a ledger without a password opens with.
  Future<String> quickSecret() async => (await _quickKey.readAsString()).trim();

  /// Drops the kept key once the person has set a password.
  Future<void> forgetQuickKey() async {
    if (await _quickKey.exists()) await _quickKey.delete();
  }

  /// Creates the ledger. Returns the recovery code, to show once; it is
  /// also kept for [takeRecoveryCode].
  Future<String> setUp(String password) async {
    final (open, recovery) = await _vault.create(password);
    await _enrolDevice(open);
    _recovery = recovery;
    _ready(open);
    return recovery;
  }

  /// The recovery code of a ledger just created, once; null after that.
  String? takeRecoveryCode() {
    final code = _recovery;
    _recovery = null;
    return code;
  }

  Future<void> unlockWithPassword(String password) async {
    final open = await _vault.unlockWithPassword(password);
    await _enrolDevice(open);
    _ready(open);
  }

  /// Restores the backup at [path] as this device's ledger. It opens
  /// with the backup's password, or its recovery code when [recovery] is
  /// set, which then open the restored ledger too.
  Future<void> restore(
    String path,
    String secret, {
    bool recovery = false,
  }) async {
    final file = File(path);
    final header = await LedgerBackup.readHeader(file);
    final keys = recovery
        ? await codec.unlockWithRecovery(header.keyring, secret)
        : await codec.unlockWithPassword(header.keyring, secret);
    final open = await _vault.restore(keys, (staging) async {
      await LedgerBackup.restore(file: file, keys: keys, into: staging);
    });
    // The restored ledger opens with the backup's own password.
    await forgetQuickKey();
    if (recovery) {
      _openedByRecovery = true;
      await _openWithoutPassword(open);
    }
    await _enrolDevice(open);
    _ready(open);
  }

  Future<void> unlockWithRecovery(String recoveryCode) async {
    final open = await _vault.unlockWithRecovery(recoveryCode);
    _openedByRecovery = true;
    _ready(await _openWithoutPassword(open));
  }

  var _openedByRecovery = false;

  /// True once after the recovery code opened the ledger, which has no
  /// password from then on, so the screens can say so.
  bool takeRecoveryNotice() {
    final opened = _openedByRecovery;
    _openedByRecovery = false;
    return opened;
  }

  Future<void> unlockWithDevice() async {
    final device = this.device;
    if (device == null) throw StateError('No device key.');
    final hasKey = device.hasKey;
    if (await _noDevice.exists()) await _noDevice.delete();
    if (hasKey != null && !await hasKey()) {
      // The key is gone: the next password unlock enrols a new one.
      _reEnrol = true;
      throw const KeyringException(KeyringError.unknownDevice);
    }
    _ready(await _vault.unlockWithDevice(device.id, device.wrapper));
  }

  /// The device's key was lost and its old entry must be replaced.
  var _reEnrol = false;

  /// Closes the database.
  void lock() {
    final state = _state;
    if (state is Ready) state.vault.close();
    _recovery = null;
    _state = _locked();
    notifyListeners();
  }

  /// Adds this device's key once, after a password unlock. A cancelled
  /// fingerprint never blocks the unlock, and is not asked again until
  /// the person asks for the fingerprint on the lock screen.
  Future<void> _enrolDevice(OpenVault open) async {
    final device = this.device;
    if (device == null) return;
    final known = open.keys.keyring.deviceIds.contains(device.id);
    if (known && !_reEnrol) return;
    if (!_reEnrol && _noDevice.existsSync()) return;
    try {
      final current = known ? open.keys.removeDevice(device.id) : open.keys;
      final keys = await current.addDevice(device.id, device.wrapper);
      await open.updateKeys(keys);
      _reEnrol = false;
    } on Object catch (error) {
      debugPrint('Device key not enrolled: $error');
      await _noDevice.writeAsString('', flush: true);
    }
  }

  void _ready(OpenVault open) {
    _state = Ready(open);
    notifyListeners();
  }

  StartupState _locked() {
    if (!_vault.exists) return const NeedsSetup();
    return Locked(
      deviceUnlock: device != null,
      askFirst: !_noDevice.existsSync(),
    );
  }
}
