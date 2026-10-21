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
