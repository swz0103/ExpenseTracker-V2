import 'package:unorm_dart/unorm_dart.dart' as unorm;

/// Decimal digits of any script, such as ０-９ typed full width.
final _digits = RegExp(r'^\p{Nd}+$', unicode: true);

/// Why a password is refused by a [PasswordPolicy].
enum PasswordProblem {
  /// Fewer characters than [PasswordPolicy.minimumLength].
  tooShort,

  /// Only digits, such as a PIN: a small space to guess from.
  allDigits,
}

/// What a password must be to be set: the one rule for the app password
/// and the backup passphrase, wherever one is set. A password set before
/// the rule changed keeps working for unlocking; only setting one checks.
///
/// Length counts Unicode code points after NFC normalization, the form a
/// password is stretched in.
final class PasswordPolicy {
  const PasswordPolicy({
    this.minimumLength = 8,
    this.digitsOnlyAllowed = false,
  });

  /// The rule every password the person sets is held to.
  ///
  /// Provisional numbers, waiting for the owner's decision: 8 characters
  /// at least, and not digits alone.
  static const standard = PasswordPolicy();

  /// The fewest code points a password may have.
  final int minimumLength;

  /// Whether a password of digits alone may be set.
  final bool digitsOnlyAllowed;

  /// The NFC form of [password], as it is stretched.
  static String normalize(String password) => unorm.nfc(password);

  /// The first rule [password] breaks, or null when it may be set.
  PasswordProblem? check(String password) {
    final normalized = normalize(password);
    if (normalized.runes.length < minimumLength) {
      return PasswordProblem.tooShort;
    }
    if (!digitsOnlyAllowed && _digits.hasMatch(normalized)) {
      return PasswordProblem.allDigits;
    }
    return null;
  }

  /// Whether a password already in use would no longer be accepted if set
  /// today, so the person can be asked to change it.
  bool isBelow(String password) => check(password) != null;
}
