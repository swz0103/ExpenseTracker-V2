import 'package:uuid/data.dart' show V4Options;
import 'package:uuid/rng.dart' show CryptoRNG;
import 'package:uuid/uuid.dart';

/// Canonical RFC 9562 version 7 public ID. Not a database row ID or a secret.
final class PublicId {
  PublicId.parse(String input) : value = input.toLowerCase() {
    if (!RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    ).hasMatch(value)) {
      throw const FormatException('Expected a UUID v7 public ID.');
    }
  }
  factory PublicId.generate() => PublicId.parse(const Uuid().v7());
  final String value;
  @override
  bool operator ==(Object other) => other is PublicId && value == other.value;
  @override
  int get hashCode => value.hashCode;
  @override
  String toString() => value;
}

/// A secret random value of one install that [NameId]s are made under, so
/// an id cannot be matched by guessing the name: an RFC 9562 version 4
/// UUID from the platform's secure random source. Kept sealed; another
/// salt makes every id anew.
final class NameSalt {
  NameSalt.parse(String input) : value = input.toLowerCase() {
    if (!_form.hasMatch(value)) {
      throw const FormatException('Expected a UUID v4 salt.');
    }
  }

  /// [input] as a salt; null when it is not one, as a value kept that was
  /// damaged.
  static NameSalt? tryParse(String input) =>
      _form.hasMatch(input.toLowerCase()) ? NameSalt.parse(input) : null;

  static final _form = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );
  factory NameSalt.generate() =>
      NameSalt.parse(const Uuid().v4(config: V4Options(null, CryptoRNG())));
  final String value;
  @override
  bool operator ==(Object other) => other is NameSalt && value == other.value;
  @override
  int get hashCode => value.hashCode;

  /// Not the value: a salt is never shown, logged or put in a message.
  @override
  String toString() => 'NameSalt(…)';
}

/// An id that stands for a name where the name must not be read, as a
/// notification's tag: the same name under the same [NameSalt] always
/// gives the same id (RFC 9562 version 5, the salt its namespace). Without
/// the salt, a name guessed cannot be checked against it.
final class NameId {
  NameId.of(String name, NameSalt salt)
    : value = const Uuid().v5(salt.value, name);

  final String value;

  @override
  bool operator ==(Object other) => other is NameId && value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}
