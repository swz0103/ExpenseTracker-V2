import 'password_policy.dart';

enum KeyringError {
  /// The keyring or recovery code is malformed.
  invalidFormat,

  /// Written by a different format version or password policy.
  unsupportedVersion,

  /// The password, recovery code or device key does not open this keyring.
  wrongSecret,

  /// A new password breaks the [PasswordPolicy]; see
  /// [KeyringException.passwordProblem].
  weakPassword,

  /// No device slot has the requested id, or the id is taken.
  unknownDevice,

  /// The keyring has no slot for this kind of secret: no password (a
  /// keyring taken from a backup) or no backup passphrase.
  noSuchSlot,
}

final class KeyringException implements Exception {
  const KeyringException(
    this.error, {
    this.passwordProblem,
    this.minimumLength,
  });

  final KeyringError error;

  /// The rule a refused password broke, for [KeyringError.weakPassword].
  /// A detail: two exceptions of the same [error] are equal.
  final PasswordProblem? passwordProblem;

  /// The fewest characters the rule a refused password broke asks for,
  /// for [KeyringError.weakPassword]: the password and the backup
  /// passphrase are held to different rules. A detail, like
  /// [passwordProblem].
  final int? minimumLength;

  @override
  bool operator ==(Object other) =>
      other is KeyringException && other.error == error;

  @override
  int get hashCode => error.hashCode;

  @override
  String toString() => 'KeyringException(${error.name})';
}
