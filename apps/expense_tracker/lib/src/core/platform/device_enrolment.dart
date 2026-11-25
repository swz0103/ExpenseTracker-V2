import 'dart:io';

import 'package:flutter/services.dart' show PlatformException;
import 'package:vault/backup_security.dart';
import 'package:vault/ledger_vault.dart';

import '../diagnostics/error_log.dart';
import 'startup_state.dart';

/// This phone's fingerprint (or face) as a key of the ledger: enrolled
/// at a password unlock unless the person turned it down, turned on and
/// off in settings, asked for on the lock screen, and enrolled again when
/// Android dropped its key. The `Startup` holds one and says when the
/// ledger opens; the keys are its open vault's.
final class DeviceEnrolment {
  DeviceEnrolment(this.device, Directory directory)
    : _noDevice = File('${directory.path}/no-fingerprint');

  final DeviceUnlock? device;

  /// Kept while the fingerprint is off: turned down when offered, or
  /// turned off in settings ([remove]). A password unlock then does not
  /// offer it; only turning it on in settings ([enrol]) drops it.
  final File _noDevice;

  /// The device's key was lost and its old entry must be replaced.
  var _reEnrol = false;

  /// What the lock screen offers of the fingerprint for a ledger kept
  /// with [keyring] (null when it cannot be read): whether there is one to
  /// ask for, or to say so about before the first password unlock, and
  /// whether to ask for it as soon as the screen opens.
  ({bool offered, bool askFirst}) onLock(Keyring? keyring) {
    final device = this.device;
    final turnedOff = _noDevice.existsSync();
    final enrolled =
        device != null && (keyring?.deviceIds.contains(device.id) ?? false);
    return (
      // Turned off in settings (or turned down when offered), there is no
      // fingerprint to ask for; before the first password unlock there is
      // one to say so about.
      offered: device != null && (enrolled || !turnedOff),
      askFirst: !turnedOff,
    );
  }

  /// Asks for the fingerprint or face and opens the ledger with [open],
  /// given the device's id and its key. Null when the person turned the
  /// prompt down themselves (改用密碼, or back): their choice, not a
  /// failure, so nothing is thrown or noted.
  Future<OpenVault?> unlock(
    Future<OpenVault> Function(String id, DeviceKeyWrapper key) open,
  ) async {
    final device = this.device;
    if (device == null) throw StateError('No device key.');
    final hasKey = device.hasKey;
    if (hasKey != null && !await hasKey()) {
      // The key is gone: the next password unlock enrols a new one.
      _reEnrol = true;
      throw const KeyringException(KeyringError.unknownDevice);
    }
    final asked = _AskedKey(device.wrapper);
    try {
      return await open(device.id, asked);
    } on KeyringException {
      if (asked.declined) return null;
      rethrow;
    }
  }

  /// Whether this phone's fingerprint opens [open].
  bool opens(OpenVault open) {
    final device = this.device;
    return device != null &&
        !_reEnrol &&
        open.keys.keyring.deviceIds.contains(device.id);
  }

  /// Turns the fingerprint on for [open], asked for in settings: the
  /// phone asks for it once to make its key. False when the person turned
  /// that prompt down; any other failure is thrown.
  Future<bool> enrol(OpenVault open) async {
    final device = this.device;
    if (device == null) throw StateError('No device key.');
    final known = open.keys.keyring.deviceIds.contains(device.id);
    try {
      final current = known ? open.keys.removeDevice(device.id) : open.keys;
      await open.updateKeys(await current.addDevice(device.id, device.wrapper));
    } on Object catch (error) {
      if (declined(error)) return false;
      rethrow;
    }
    _reEnrol = false;
    if (await _noDevice.exists()) await _noDevice.delete();
    return true;
  }

  /// Turns the fingerprint off: its key no longer opens [open], and a
  /// password unlock does not ask to enrol it again until it is turned on
  /// in settings. False when this phone has no fingerprint key.
  Future<bool> remove(OpenVault open) async {
    final device = this.device;
    if (device == null) return false;
    await _noDevice.writeAsString('', flush: true);
    if (open.keys.keyring.deviceIds.contains(device.id)) {
      await open.updateKeys(open.keys.removeDevice(device.id));
    }
    _reEnrol = false;
    return true;
  }

  /// Adds this device's key to [open] once, after a password unlock. A
  /// cancelled fingerprint never blocks the unlock, and is not asked again
  /// until the person asks for the fingerprint on the lock screen.
  Future<void> afterPassword(OpenVault open) async {
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
      // Only turning the prompt down stops it, and that is the person's
      // choice, not a fault to note; a failure is noted and asks next
      // time.
      if (declined(error)) {
        await _noDevice.writeAsString('', flush: true);
      } else {
        ErrorLog.instance.record('生物辨識登記', error);
      }
    }
  }

  /// Whether [error] is the person turning the fingerprint prompt down
  /// (`DeviceKeyBlob.refusal` on Android), rather than a failure.
  static bool declined(Object error) =>
      error is PlatformException && error.code == 'declined';
}

/// The fingerprint key while it is asked to open the ledger, noting
/// whether the person turned the prompt down: the vault says only that
/// the key did not open.
final class _AskedKey implements DeviceKeyWrapper {
  _AskedKey(this._key);

  final DeviceKeyWrapper _key;
  var declined = false;

  @override
  Future<List<int>> wrap(List<int> secret, List<int> context) =>
      _key.wrap(secret, context);

  @override
  Future<List<int>> unwrap(List<int> wrapped, List<int> context) async {
    try {
      return await _key.unwrap(wrapped, context);
    } on Object catch (error) {
      declined = DeviceEnrolment.declined(error);
      rethrow;
    }
  }
}
