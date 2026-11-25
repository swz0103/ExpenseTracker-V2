import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:storage/storage.dart' show EncryptedDatabase;
import 'package:vault/backup_security.dart';
import 'package:vault/ledger_backup.dart';
import 'package:vault/ledger_vault.dart';

import '../diagnostics/error_log.dart';
import '../diagnostics/error_steps.dart';
import '../time/app_clock.dart';
import 'book_damage.dart';
import 'device_enrolment.dart';
import 'ledger_folder.dart';
import 'memory_keystore.dart';
import 'quick_key.dart';
import 'unlock_attempts.dart';
import 'staged_photos.dart';
import 'startup_state.dart';

/// From app launch to an unlocked session. The screens only show the
/// [state] and call these methods; keys never leave this class and the
/// vault. The parts that hold no key of their own are kept apart: the
/// fingerprint ([DeviceEnrolment]), a damaged book ([BookDamage]), the
/// key of a ledger without a password ([QuickKey]) and the files beside
/// the ledger ([LedgerFolder]); the states are in startup_state.dart.
final class Startup extends ChangeNotifier {
  /// [quickKey] seals the key of a ledger opened without a password: on
  /// Android a Keystore key that needs no fingerprint, so the ledger opens
  /// by itself while the key never lies on disk in plain form; elsewhere
  /// [MemoryKeystore].
  ///
  /// [uptime] is the phone's clock that no setting moves, for the wait
  /// after wrong passwords ([UnlockAttempts]).
  Startup(
    this._vault, {
    DeviceUnlock? device,
    this.check,
    this.checkRestored,
    DeviceKeyWrapper? quickKey,
    UptimeSource? uptime,
  }) : folder = LedgerFolder(_vault.directory),
       _devices = DeviceEnrolment(device, _vault.directory),
       _quick = QuickKey(_vault.directory, quickKey ?? MemoryKeystore.instance),
       _attempts = UnlockAttempts(
         File('${_vault.directory.path}/unlock-attempts.json'),
         uptime: uptime,
       ) {
    _state = _locked();
  }

  /// The wrong passwords and recovery codes typed in a row, and the wait
  /// they cost.
  final UnlockAttempts _attempts;

  /// How long until a password or recovery code may be tried again; zero
  /// when one may be now.
  Future<Duration> unlockWait() => _attempts.wait();

  /// Opens with a typed secret through the attempt limit: refused with
  /// [UnlockDelayed] while a wait is on, and a wrong secret counted.
  Future<OpenVault> _limited(Future<OpenVault> Function() open) async {
    final wait = await _attempts.wait();
    if (wait > Duration.zero) throw UnlockDelayed(wait);
    try {
      return await _watchDamage(open);
    } on KeyringException catch (error) {
      if (error.error == KeyringError.wrongSecret) await _attempts.failed();
      rethrow;
    }
  }

  /// The ledger's database found damaged: one handling at a time, made
  /// again from its records or set aside.
  late final _book = BookDamage(_vault, (
    close: _closeDamaged,
    damaged: _damaged,
    locked: ({bool noSpace = false}) {
      _state = _locked(noSpace: noSpace);
      notifyListeners();
    },
    ready: _ready,
  ));

  Future<OpenVault> _watchDamage(Future<OpenVault> Function() open) =>
      _book.watch(open);

  void _damaged(Object error) {
    ErrorLog.instance.record(ErrorSteps.bookDamaged, error);
    _state = const Damaged();
    notifyListeners();
  }

  /// Closes the book found damaged; the keys it was open with.
  UnlockedKeyring? _closeDamaged() {
    final state = _state;
    final keys = state is Ready ? state.vault.keys : null;
    if (state is Ready) state.vault.close();
    _recovery = null;
    _newPassword = false;
    _resume = null;
    return keys;
  }

  /// [BookDamage.bookDamaged].
  Future<void> bookDamaged(Object error) => _book.bookDamaged(error);

  /// [BookDamage.journalDamaged], told whether a book is open.
  Future<bool> journalDamaged(Object error) =>
      _book.journalDamaged(error, bookOpen: _state is Ready);

  /// [BookDamage.reading].
  Future<T> readingBook<T>(Future<T> read) => _book.reading(read);

  /// From [Damaged], back to the lock screen to try again.
  void retryAfterDamage() {
    _state = _locked();
    notifyListeners();
  }

  final LedgerVault _vault;

  /// The files beside the ledger that say what became of it.
  final LedgerFolder folder;

  /// This phone's fingerprint as a key of the ledger.
  final DeviceEnrolment _devices;
  DeviceUnlock? get device => _devices.device;

  /// The key of a ledger opened without a password, sealed, until the
  /// person sets a password.
  final QuickKey _quick;

  /// Throws for a record the app cannot read, so a backup holding one is
  /// refused rather than restored.
  final void Function(String collection, String id, String body)? check;

  /// Throws for a book restored, read whole, that the app cannot keep
  /// though each record reads (D103: categories on a loop of parents),
  /// so it is refused rather than put in place.
  final void Function(EncryptedDatabase restored)? checkRestored;
  late StartupState _state;
  String? _recovery;

  StartupState get state => _state;

  /// Where the ledger's files are kept.
  Directory get directory => _vault.directory;

  /// Opens and checks the ledger's keys.
  KeyringCodec get codec => _vault.codec;

  /// The ledger opens without asking: no password has been set.
  bool get passwordless => _quick.exists;

  /// Creates the ledger without asking for anything: a random key, sealed
  /// by the phone's Keystore, opens it, and a password can be set later.
  /// Its recovery code is shown once ([takeRecoveryCode]): the copy
  /// Android takes to the person's Google account opens with it on a new
  /// phone.
  Future<void> setUpWithoutPassword() async {
    await directory.create(recursive: true);
    await folder.setAsideCloudCopy();
    final secret = QuickKey.newSecret();
    final (open, recovery) = await _quick.keepOnce(
      secret,
      () => _vault.create(secret),
    );
    _recovery = recovery;
    await folder.recoveryGiven.writeAsString('', flush: true);
    _fresh = true;
    _ready(open, newBook: true);
  }

  /// The copy Android brought back with no ledger here yet: when it was
  /// taken and how many records it holds. Null when there is none.
  Future<BackupHeader?> broughtBack() async =>
      _state is NeedsSetup ? folder.cloudCopyHeader() : null;

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

  /// Opens a ledger set up without a password. One whose recovery code
  /// was never shown gets a new one, shown once ([takeRecoveryCode]): the
  /// copy Android takes to the person's Google account opens with it.
  Future<void> openQuietly() async {
    final open = await _quick.open(
      (key) => _watchDamage(() => _vault.unlockWithPassword(key)),
    );
    if (!folder.recoveryGiven.existsSync()) {
      final rotated = await open.keys.rotateRecovery();
      await open.updateKeys(rotated.unlocked);
      await folder.recoveryGiven.writeAsString('', flush: true);
      _recovery = rotated.recoveryCode;
    }
    _ready(open);
  }

  /// The key a ledger without a password opens with. One kept in plain
  /// form by an earlier version is sealed now, and the plain file
  /// overwritten and deleted.
  Future<String> quickSecret() => _quick.secret();

  /// Drops the kept key once the person has set a password.
  Future<void> forgetQuickKey() => _quick.forget();

  /// Creates the ledger. Returns the recovery code, to show once; it is
  /// also kept for [takeRecoveryCode].
  Future<String> setUp(String password) async {
    // A key left by an earlier try without a password opens nothing now.
    await forgetQuickKey();
    await folder.setAsideCloudCopy();
    final (open, recovery) = await _vault.create(password);
    await _devices.afterPassword(open);
    _recovery = recovery;
    _ready(open, newBook: true);
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

  /// When the keys were last replaced in this run ([resetKeys]), taken
  /// just before: a backup written before it was sealed with the old keys.
  DateTime? get keysResetAt => _keysResetAt;
  DateTime? _keysResetAt;

  /// Whether the code [takeRecoveryCode] gives comes from resetting the
  /// keys, once.
  bool takeKeysReset() {
    final reset = _keysReset;
    _keysReset = false;
    return reset;
  }

  /// Opens the ledger with its password. Throws [UnlockDelayed] while the
  /// wait after wrong tries is on, without trying [password].
  Future<void> unlockWithPassword(String password) async {
    final open = await _limited(() => _vault.unlockWithPassword(password));
    _belowRule = codec.policy.isBelow(password);
    await _devices.afterPassword(open);
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
  ///
  /// [revisionAtLeast] is the most the app layer knows a backup of this
  /// phone's ledger to have been delivered or to wait at (the folder's,
  /// Drive's, the outbox's): the restored book goes on from above it and
  /// from above what [_revisionBefore] reads, so it passes every
  /// delivered revision and a new backup is due (review 28).
  Future<void> restore(
    String path,
    String secret, {
    bool recovery = false,
    int revisionAtLeast = 0,
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
    final photos = StagedPhotos(_vault.stagedFiles);
    final open = await _vault.restore(
      keys,
      replacing: replacing,
      revisionBefore: max(revisionAtLeast, await _revisionBefore()),
      (staging) async {
        await LedgerBackup.restore(
          file: file,
          keys: keys,
          into: staging,
          accept: check,
          onFile: photos.add,
        );
        checkRestored?.call(staging);
      },
    );
    photos.noteSkipped();
    // The restored ledger opens with the backup's own keys.
    await forgetQuickKey();
    _replacedLedger = null;
    if (!byPassword) {
      // The code was just typed: the person has it.
      await folder.recoveryGiven.writeAsString('', flush: true);
      _newPassword = true;
    }
    await _devices.afterPassword(open);
    _ready(open, newBook: true);
  }

  /// The most this phone's ledger is known to have stood at, read without
  /// its keys: the backup of it kept before a restore from settings
  /// ([replacedLedger]) and the copy kept for Android's cloud backup
  /// ([LedgerFolder.cloudCopy]); 0 when neither says. A restore goes on from above it
  /// ([LedgerVault.restore]), which also reads the ledger it replaces
  /// where the backup's keys open it.
  Future<int> _revisionBefore() async {
    final before = _replacedLedger?.revision ?? 0;
    final copy = await folder.cloudCopyHeader();
    return copy == null ? before : max(before, copy.revision);
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
  /// Wrong codes are counted and slowed down as wrong passwords are
  /// ([UnlockDelayed]).
  Future<void> unlockWithRecovery(String secret) async {
    final open = await _limited(
      () => looksLikeRecoveryCode(secret) || !_lockedWithPassphrase
          ? _vault.unlockWithRecovery(secret)
          : _vault.unlockWithPassphrase(secret),
    );
    // The code was just typed: the person has it.
    await folder.recoveryGiven.writeAsString('', flush: true);
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
    final secret = QuickKey.newSecret();
    await _quick.keepOnce(
      secret,
      () async => open.updateKeys(await open.keys.changePassword(secret)),
    );
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
      secret = QuickKey.newSecret();
    } else {
      if (password == null) throw ArgumentError.notNull('password');
      // Throws for a wrong one, before anything changes.
      await codec.unlockWithPassword(open.keys.keyring, password);
      secret = password;
    }
    final at = AppClock.now();
    final reset = await open.keys.reset(password: secret);
    if (quick) await _quick.write(_quick.next, secret);
    final OpenVault next;
    try {
      next = await _vault.resetKeys(open, reset.unlocked);
    } on Object {
      if (quick && _quick.next.existsSync()) await _quick.next.delete();
      rethrow;
    }
    if (quick) await _quick.next.rename(_quick.sealed.path);
    await folder.recoveryGiven.writeAsString('', flush: true);
    _recovery = reset.recoveryCode;
    _keysReset = true;
    _keysResetAt = at;
    _ready(next, newBook: true);
  }

  /// Asks for the fingerprint or face and opens the ledger with it. False
  /// when the person turned the prompt down themselves (改用密碼, or
  /// back): their choice, not a failure, so nothing is thrown or noted.
  Future<bool> unlockWithDevice() async {
    final open = await _devices.unlock(
      (id, key) => _watchDamage(() => _vault.unlockWithDevice(id, key)),
    );
    if (open == null) return false;
    _ready(open);
    return true;
  }

  /// Whether this phone's fingerprint opens the ledger now open.
  bool get deviceEnrolled => switch (_state) {
    Ready(:final vault) => _devices.opens(vault),
    _ => false,
  };

  /// Turns the fingerprint on for the open ledger, asked for in settings:
  /// the phone asks for it once to make its key. False when the person
  /// turned that prompt down; any other failure is thrown.
  Future<bool> enrolDevice() async {
    if (!await _devices.enrol((_state as Ready).vault)) return false;
    notifyListeners();
    return true;
  }

  /// Turns the fingerprint off: its key no longer opens the ledger, and a
  /// password unlock does not ask to enrol it again until it is turned on
  /// in settings.
  Future<void> removeDevice() async {
    if (device == null) return;
    if (await _devices.remove((_state as Ready).vault)) notifyListeners();
  }

  /// Closes the database, and opens the lock screen on restoring a
  /// backup in place of this ledger: from settings, after a backup of
  /// this one was kept at [kept], so a restore can say what it replaces.
  ///
  /// The keys the ledger was open with are held in memory until the
  /// restore is done, given up ([cancelRestore]) or the app locks
  /// ([lock]), so giving it up needs no password again.
  void lockToRestore([BackupHeader? kept]) {
    final state = _state;
    _restoreNext = true;
    _replacedLedger = kept;
    _close(resume: state is Ready ? state.vault.keys : null);
  }

  /// The keys of the ledger closed for a restore from settings.
  UnlockedKeyring? _resume;

  /// Whether a restore from settings can be given up without unlocking
  /// again: the ledger was closed for it and the app has not locked
  /// since.
  bool get canResume => _resume != null && _state is Locked;

  /// The restore from settings is given up: the ledger opens again as it
  /// was, with the keys it was open with. Without them ([canResume] is
  /// false) nothing happens, and the lock screen asks as usual.
  Future<void> cancelRestore() async {
    final keys = _resume;
    if (keys == null || _state is! Locked) return;
    _resume = null;
    _replacedLedger = null;
    _restoreNext = false;
    final open = await _watchDamage(() => _vault.reopen(keys));
    _resumed = true;
    _ready(open);
  }

  var _resumed = false;

  /// Whether the ledger now open is the one a restore was given up for
  /// ([cancelRestore]), once: the app then goes back to where the person
  /// was.
  bool takeResumed() {
    final resumed = _resumed;
    _resumed = false;
    return resumed;
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

  /// Closes the database, and lets go of keys held for a restore.
  void lock() => _close();

  void _close({UnlockedKeyring? resume}) {
    final state = _state;
    if (state is Ready) state.vault.close();
    _recovery = null;
    _newPassword = false;
    _resume = resume;
    _resumed = false;
    _state = _locked();
    notifyListeners();
  }

  /// How many times in this run a book was put in place of the one
  /// before: made, restored or opened on keys just reset. Not a plain
  /// unlock, which opens the same book.
  int get bookChanges => _bookChanges;
  var _bookChanges = 0;

  void _ready(OpenVault open, {bool newBook = false}) {
    if (newBook) _bookChanges++;
    _opening = false;
    _resume = null;
    // The ledger opened: wrong tries before it are forgotten.
    _attempts.clear();
    _state = Ready(open);
    notifyListeners();
  }

  StartupState _locked({bool noSpace = false}) {
    _quick.settle(ledgerExists: _vault.exists);
    if (!_vault.exists) return const NeedsSetup();
    final keyring = _keyring();
    final fingerprint = _devices.onLock(keyring);
    return Locked(
      deviceUnlock: fingerprint.offered,
      askFirst: fingerprint.askFirst,
      passphrase: keyring?.hasPassphrase ?? false,
      noSpace: noSpace,
    );
  }

  /// The keyring as it is kept, to say what the lock screen offers; null
  /// when it cannot be read.
  Keyring? _keyring() {
    try {
      return Keyring.parse(_vault.keyringFile.readAsStringSync());
    } on Object catch (error) {
      // Read again by the unlock, which says what is wrong.
      ErrorLog.instance.record('讀取金鑰', error);
      return null;
    }
  }
}
