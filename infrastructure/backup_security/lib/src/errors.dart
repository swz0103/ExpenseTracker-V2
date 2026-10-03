enum KeyringError {
  /// The keyring or recovery code is malformed.
  invalidFormat,

  /// Written by a different format version or password policy.
  unsupportedVersion,

  /// The password, recovery code or device key does not open this keyring.
  wrongSecret,

  /// A new password is shorter than the policy allows.
  weakPassword,

  /// No device slot has the requested id, or the id is taken.
  unknownDevice,
}

final class KeyringException implements Exception {
  const KeyringException(this.error);

  final KeyringError error;

  @override
  bool operator ==(Object other) =>
      other is KeyringException && other.error == error;

  @override
  int get hashCode => error.hashCode;

  @override
  String toString() => 'KeyringException(${error.name})';
}
