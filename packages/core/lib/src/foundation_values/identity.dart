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

/// An id that stands for a name where the name must not be read, as a
/// notification's tag: the same name always gives the same id (RFC 9562
/// version 5, under [namespace]). Not a secret: a name guessed can be
/// checked against it; it keeps the name out of what is merely looked at.
final class NameId {
  NameId.of(String name) : value = const Uuid().v5(namespace, name);

  /// The app's own namespace for these ids; changing it changes them all.
  static const namespace = '6f2b7c1e-3d4a-5b8c-9e0f-1a2b3c4d5e6f';

  final String value;

  @override
  bool operator ==(Object other) => other is NameId && value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}
