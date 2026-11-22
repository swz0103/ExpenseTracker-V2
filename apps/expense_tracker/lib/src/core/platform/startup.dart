import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:vault/backup_security.dart';
import 'package:vault/ledger_backup.dart';
import 'package:vault/ledger_vault.dart';

import '../diagnostics/error_log.dart';
import '../time/app_clock.dart';
import 'memory_keystore.dart';

/// What a backup says of itself before any key: when it was taken, its
/// records, and what opens it. Named here for the screens, which do not
/// reach into the vault.
typedef BackupFacts = BackupHeader;

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
  const Locked({
    required this.deviceUnlock,
    this.askFirst = true,
    this.passphrase = false,
  });

  /// This device has a key to try before asking for the password. It is
  /// enrolled at the first password unlock; until then the device unlock
  /// fails with `KeyringError.unknownDevice`.
  final bool deviceUnlock;

  /// Whether to ask for the fingerprint as soon as the screen opens: not
  /// after the person turned enrolling it down.
  final bool askFirst;

  /// Whether a backup passphrase opens the ledger too, where the recovery
  /// code is asked for.
  final bool passphrase;
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
  /// [quickKey] seals the key of a ledger opened without a password: on
  /// Android a Keystore key that needs no fingerprint, so the ledger opens
  /// by itself while the key never lies on disk in plain form; elsewhere
  /// [MemoryKeystore].
  Startup(this._vault, {this.device, this.check, DeviceKeyWrapper? quickKey})
    : _quickKeystore = quickKey ?? MemoryKeystore.instance {
    _state = _locked();
  }

  final LedgerVault _vault;
  final DeviceUnlock? device;
  final DeviceKeyWrapper _quickKeystore;

  /// Throws for a record the app cannot read, so a backup holding one is
  /// refused rather than restored.
  final void Function(String collection, String id, String body)? check;
  late StartupState _state;
  String? _recovery;

  StartupState get state => _state;

  /// Where the ledger's files are kept.
  Directory get directory => _vault.directory;

  /// Opens and checks the ledger's keys.
  KeyringCodec get codec => _vault.codec;

  /// The key of a ledger opened without a password, sealed by the
  /// [_quickKeystore], until the person sets a password.
  File get _sealedKey => File('${directory.path}/quick-open.sealed');

  /// Where versions before 0.23 kept that key in plain form. Read once,
  /// sealed, then overwritten and deleted ([quickSecret]).
  File get _plainKey => File('${directory.path}/quick-open.key');

  /// A new sealed key written before the keys are reset, named over
  /// [_sealedKey] after ([resetKeys]).
  File get _nextSealedKey => File('${_sealedKey.path}.next');

  static final _quickContext = utf8.encode('expense_tracker/quick-open');

  /// Kept when the person turned the fingerprint down, so a password
  /// unlock stops asking; asking for the fingerprint drops it.
  File get _noDevice => File('${directory.path}/no-fingerprint');

  /// The ledger opens without asking: no password has been set.
  bool get passwordless => _sealedKey.existsSync() || _plainKey.existsSync();

  /// Creates the ledger without asking for anything: a random key, sealed
  /// by the phone's Keystore, opens it, and a password can be set later.
  /// Its recovery code is shown once ([takeRecoveryCode]): the copy
  /// Android takes to the person's Google account opens with it on a new
  /// phone.
  Future<void> setUpWithoutPassword() async {
    await directory.create(recursive: true);
    await _setAsideCloudCopy();
    final secret = _newSecret();
    // Kept aside until the ledger it opens exists: a key with no ledger
    // would say there is no password for a ledger never made.
    final pending = File('${_sealedKey.path}.new');
    await _writeSealed(pending, secret);
    final (open, recovery) = await _vault.create(secret);
    await pending.rename(_sealedKey.path);
    _recovery = recovery;
    await recoveryGiven.writeAsString('', flush: true);
    _fresh = true;
    _ready(open);
  }

  /// Kept once this ledger's recovery code has been shown, so a backup
  /// leaving the phone does not make a new one (encrypted_backup_manager.dart).
  File get recoveryGiven => File('${directory.path}/recovery-given');

  /// The copy of the ledger, without its photos, that Android's own
  /// backup takes to the person's Google account and brings back when the
  /// app is installed again or on a new phone (res/xml): the only file
  /// it takes.
  File get cloudCopy => File('${directory.path}/cloud/記帳本.etbk');

  /// The copy Android brought back with no ledger here yet: when it was
  /// taken and how many records it holds. Null when there is none.
  Future<BackupHeader?> broughtBack() async {
    if (_state is! NeedsSetup || !cloudCopy.existsSync()) return null;
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
  Future<void> _setAsideCloudCopy() async {
    final copy = cloudCopy;
    if (!copy.existsSync()) return;
    await beforeRestore.create(recursive: true);
    await copy.rename(
      '${beforeRestore.path}/brought-back-'
      '${AppClock.now().millisecondsSinceEpoch}.etbk',
    );
  }

  var _fresh = false;

  /// Whether the ledger now open was just started empty on this phone,
  /// once: the app then walks through its main places.
  bool takeFresh() {
    final fresh = _fresh;
    _fresh = false;
    return fresh;
  }

  var _opening = true;

  /// Whether the app has just started and not yet played its opening
  /// animation, once: a ledger locked again later goes straight to the
  /// password.
  bool takeOpening() {
    final opening = _opening;
    _opening = false;
    return opening;
  }

  static String _newSecret() {
    final random = Random.secure();
    return base64Url.encode([for (var i = 0; i < 32; i++) random.nextInt(256)]);
  }

  /// Seals [secret] with the phone's Keystore into [file], written in full
  /// before anything names it.
  Future<void> _writeSealed(File file, String secret) async {
    final blob = await _quickKeystore.wrap(utf8.encode(secret), _quickContext);
    await file.writeAsBytes(blob, flush: true);
  }

  Future<String> _readSealed(File file) async => utf8.decode(
    await _quickKeystore.unwrap(await file.readAsBytes(), _quickContext),
  );

  /// Opens a ledger set up without a password. One whose recovery code
  /// was never shown gets a new one, shown once ([takeRecoveryCode]): the
  /// copy Android takes to the person's Google account opens with it.
  Future<void> openQuietly() async {
    final open = await _openWithQuickKey();
    if (!recoveryGiven.existsSync()) {
      final rotated = await open.keys.rotateRecovery();
      await open.updateKeys(rotated.unlocked);
      await recoveryGiven.writeAsString('', flush: true);
      _recovery = rotated.recoveryCode;
    }
    _ready(open);
  }

  /// A reset of the keys stopped before its new sealed key was named:
  /// whichever of the two opens the keyring is the ledger's.
  Future<OpenVault> _openWithQuickKey() async {
    final next = _nextSealedKey;
    if (next.existsSync()) {
      try {
        final open = await _vault.unlockWithPassword(await _readSealed(next));
        await next.rename(_sealedKey.path);
        return open;
      } on KeyringException catch (error) {
        // The reset never finished: the old key is still the ledger's.
        ErrorLog.instance.record('重設金鑰', error);
        await next.delete();
      }
    }
    return _vault.unlockWithPassword(await quickSecret());
  }

  /// The key a ledger without a password opens with. One kept in plain
  /// form by an earlier version is sealed now, and the plain file
  /// overwritten and deleted.
  Future<String> quickSecret() async {
    final plain = _plainKey;
    if (plain.existsSync()) {
      final secret = (await plain.readAsString()).trim();
      final pending = File('${_sealedKey.path}.new');
      await _writeSealed(pending, secret);
      await pending.rename(_sealedKey.path);
      await _shred(plain);
      return secret;
    }
    return _readSealed(_sealedKey);
  }

  /// Overwrites [file] with zeros before deleting it, so its words are
  /// not left in the free space of the file system it was on.
  static Future<void> _shred(File file) async {
    if (!file.existsSync()) return;
    final length = await file.length();
    await file.writeAsBytes(Uint8List(length), flush: true);
    await file.delete();
  }

  /// Drops the kept key once the person has set a password.
  Future<void> forgetQuickKey() async {
    await _shred(_plainKey);
    for (final file in [_sealedKey, _nextSealedKey]) {
      if (await file.exists()) await file.delete();
    }
  }

  /// Creates the ledger. Returns the recovery code, to show once; it is
  /// also kept for [takeRecoveryCode].
  Future<String> setUp(String password) async {
    // A key left by an earlier try without a password opens nothing now.
    await forgetQuickKey();
    await _setAsideCloudCopy();
    final (open, recovery) = await _vault.create(password);
    await _enrolDevice(open);
    _recovery = recovery;
    _ready(open);
    return recovery;
  }

  /// The recovery code of a ledger just created, or of keys just reset,
  /// once; null after that.
  String? takeRecoveryCode() {
    final code = _recovery;
    _recovery = null;
    return code;
  }

  var _keysReset = false;

  /// Whether the code [takeRecoveryCode] gives comes from resetting the
  /// keys, once.
  bool takeKeysReset() {
    final reset = _keysReset;
    _keysReset = false;
    return reset;
  }

  Future<void> unlockWithPassword(String password) async {
    final open = await _vault.unlockWithPassword(password);
    _belowRule = codec.policy.isBelow(password);
    await _enrolDevice(open);
    _ready(open);
  }

  var _belowRule = false;

  /// Whether the password this ledger was last opened with in this run
  /// is shorter or simpler than one set today may be. It keeps working;
  /// the settings suggest changing it.
  bool get passwordBelowRule => _belowRule;

  /// Restores the backup at [path] as this device's ledger. With
  /// [recovery], [secret] is its recovery code or backup passphrase;
  /// otherwise the password a version 3 backup still carries, or the
  /// backup passphrase. A backup opened by anything but the password
  /// leaves this phone's ledger asking for a new password
  /// ([needsNewPassword]).
  Future<void> restore(
    String path,
    String secret, {
    bool recovery = false,
  }) async {
    final file = File(path);
    final header = await LedgerBackup.readHeader(file);
    final keyring = header.keyring;
    final byPassword = !recovery && keyring.hasPassword;
    final keys = byPassword
        ? await codec.unlockWithPassword(keyring, secret)
        : await _unlockWithCodeOrPassphrase(keyring, secret);
    // From settings, the closed ledger is replaced; a backup of it was
    // kept first.
    final replacing = _state is Locked;
    final staged = Directory('${_vault.stagedFiles.path}/receipts');
    var skipped = 0;
    final open = await _vault.restore(keys, replacing: replacing, (
      staging,
    ) async {
      await LedgerBackup.restore(
        file: file,
        keys: keys,
        into: staging,
        accept: check,
        // Receipt photos the backup carries, still sealed: they open with
        // the restored ledger's own key. Staged, and moved in only with
        // the checked database.
        onFile: (name, bytes) async {
          if (!RegExp(r'^[\w.-]+$').hasMatch(name)) {
            skipped++;
            return;
          }
          await staged.create(recursive: true);
          await File('${staged.path}/$name').writeAsBytes(bytes, flush: true);
        },
      );
    });
    if (skipped > 0) {
      ErrorLog.instance.record(
        '還原備份',
        StateError('$skipped files with names not kept were skipped'),
      );
    }
    // The restored ledger opens with the backup's own keys.
    await forgetQuickKey();
    _replacedLedger = null;
    if (!byPassword) {
      // The code was just typed: the person has it.
      await recoveryGiven.writeAsString('', flush: true);
      _newPassword = true;
    }
    await _enrolDevice(open);
    _ready(open);
  }

  Future<UnlockedKeyring> _unlockWithCodeOrPassphrase(
    Keyring keyring,
    String secret,
  ) => looksLikeRecoveryCode(secret) || !keyring.hasPassphrase
      ? codec.unlockWithRecovery(keyring, secret)
      : codec.unlockWithPassphrase(keyring, secret);

  /// Opens the ledger with its recovery code, or its backup passphrase.
  /// The password stays as it was, and opens it still, until the person
  /// sets a new one, which the app asks for at once ([needsNewPassword]).
  Future<void> unlockWithRecovery(String secret) async {
    final open = looksLikeRecoveryCode(secret) || !_lockedWithPassphrase
        ? await _vault.unlockWithRecovery(secret)
        : await _vault.unlockWithPassphrase(secret);
    // The code was just typed: the person has it.
    await recoveryGiven.writeAsString('', flush: true);
    _newPassword = true;
    _ready(open);
  }

  bool get _lockedWithPassphrase => switch (_state) {
    Locked(:final passphrase) => passphrase,
    _ => false,
  };

  var _newPassword = false;

  /// The ledger was opened with the recovery code (or restored from a
  /// backup without its password): the app asks for a new password before
  /// anything else, until one is set or the person chooses explicitly to
  /// open it without one.
  bool get needsNewPassword => _newPassword && _state is Ready;

  /// Sets [next] as the password of the open ledger, asked for after the
  /// recovery code opened it. It is held to the password policy.
  Future<void> setNewPassword(String next) async {
    final open = (_state as Ready).vault;
    await open.updateKeys(await open.keys.changePassword(next));
    await forgetQuickKey();
    _belowRule = false;
    _newPassword = false;
    notifyListeners();
  }

  /// The person chose to open the ledger without a password from now on:
  /// a new random key, sealed by the phone, replaces the password.
  Future<void> openWithoutPassword() async {
    final open = (_state as Ready).vault;
    final secret = _newSecret();
    final pending = File('${_sealedKey.path}.new');
    await _writeSealed(pending, secret);
    await open.updateKeys(await open.keys.changePassword(secret));
    await pending.rename(_sealedKey.path);
    _belowRule = false;
    _newPassword = false;
    notifyListeners();
  }

  /// Replaces every key of the open ledger (`LedgerVault.resetKeys`): the
  /// database and the receipt photos are encrypted again, the backups to
  /// come use a new key, and a new recovery code is shown once
  /// ([takeRecoveryCode]). [password] is the one in use, which keeps
  /// opening it; a ledger without a password gets a new sealed key. The
  /// app opens the ledger afresh on the new keys.
  Future<void> resetKeys({String? password}) async {
    final open = (_state as Ready).vault;
    final quick = passwordless;
    final String secret;
    if (quick) {
      secret = _newSecret();
    } else {
      if (password == null) throw ArgumentError.notNull('password');
      // Throws for a wrong one, before anything changes.
      await codec.unlockWithPassword(open.keys.keyring, password);
      secret = password;
    }
    final reset = await open.keys.reset(password: secret);
    if (quick) await _writeSealed(_nextSealedKey, secret);
    final OpenVault next;
    try {
      next = await _vault.resetKeys(open, reset.unlocked);
    } on Object {
      if (quick && _nextSealedKey.existsSync()) {
        await _nextSealedKey.delete();
      }
      rethrow;
    }
    if (quick) await _nextSealedKey.rename(_sealedKey.path);
    await recoveryGiven.writeAsString('', flush: true);
    _recovery = reset.recoveryCode;
    _keysReset = true;
    _ready(next);
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

  /// Closes the database, and opens the lock screen on restoring a
  /// backup in place of this ledger: from settings, after a backup of
  /// this one was kept at [kept], so a restore can say what it replaces.
  void lockToRestore([BackupHeader? kept]) {
    _restoreNext = true;
    _replacedLedger = kept;
    lock();
  }

  /// Whether the lock screen should open on restoring a backup; asked
  /// once.
  bool takeRestore() {
    final next = _restoreNext;
    _restoreNext = false;
    return next;
  }

  var _restoreNext = false;

  /// The ledger a restore from settings would replace, as the backup of
  /// it kept just before describes it; null when there is none.
  BackupHeader? get replacedLedger => _replacedLedger;
  BackupHeader? _replacedLedger;

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

  /// Closes the database.
  void lock() {
    final state = _state;
    if (state is Ready) state.vault.close();
    _recovery = null;
    _newPassword = false;
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
      ErrorLog.instance.record('指紋登記', error);
      // Only turning the prompt down stops it; a failure asks next time.
      if (error is PlatformException && error.code == 'declined') {
        await _noDevice.writeAsString('', flush: true);
      }
    }
  }

  /// A set-up without a password stopped part way: the key kept aside
  /// is the ledger's when the ledger was made, and nothing otherwise. A
  /// plain one left by an earlier version is never named, only removed.
  void _settleQuickKey() {
    final pending = File('${_sealedKey.path}.new');
    if (pending.existsSync()) {
      if (_vault.exists && !passwordless) {
        pending.renameSync(_sealedKey.path);
      } else {
        pending.deleteSync();
      }
    }
    final plainPending = File('${_plainKey.path}.new');
    if (plainPending.existsSync()) {
      if (_vault.exists && !passwordless) {
        // Sealed when the ledger opens (quickSecret).
        plainPending.renameSync(_plainKey.path);
      } else {
        plainPending
          ..writeAsBytesSync(Uint8List(plainPending.lengthSync()), flush: true)
          ..deleteSync();
      }
    }
  }

  void _ready(OpenVault open) {
    _opening = false;
    _state = Ready(open);
    notifyListeners();
  }

  StartupState _locked() {
    _settleQuickKey();
    if (!_vault.exists) return const NeedsSetup();
    return Locked(
      deviceUnlock: device != null,
      askFirst: !_noDevice.existsSync(),
      passphrase: _keyringHasPassphrase(),
    );
  }

  bool _keyringHasPassphrase() {
    try {
      return Keyring.parse(_vault.keyringFile.readAsStringSync()).hasPassphrase;
    } on Object catch (error) {
      // Read again by the unlock, which says what is wrong.
      ErrorLog.instance.record('讀取金鑰', error);
      return false;
    }
  }
}
