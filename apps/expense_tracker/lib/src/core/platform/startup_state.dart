import 'package:vault/backup_security.dart' show DeviceKeyWrapper;
import 'package:vault/ledger_backup.dart' show BackupHeader;
import 'package:vault/ledger_vault.dart' show OpenVault;

import '../diagnostics/app_fault.dart';

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
    this.noSpace = false,
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

  /// Back here because making the book again found the phone full
  /// (review 29): the screen says so before anything is tried.
  final bool noSpace;
}

/// The ledger's database is damaged (D94): empty, cut short or a page of
/// it unreadable. It is set aside as it is, never written over, and no
/// empty book is started in its place; a backup restores the ledger.
final class Damaged extends StartupState {
  const Damaged();
}

/// Unlocked and ready.
final class Ready extends StartupState {
  const Ready(this.vault);

  final OpenVault vault;
}

/// A password or recovery code was not tried: too many wrong ones came
/// before it, and the next may be tried after [wait].
final class UnlockDelayed implements AppFault {
  const UnlockDelayed(this.wait);

  final Duration wait;

  @override
  String toString() => 'UnlockDelayed';
}
