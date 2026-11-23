import 'calendar_day.dart';

/// An absolute instant serialized in UTC, distinct from a business date.
final class UtcInstant implements Comparable<UtcInstant> {
  UtcInstant(DateTime input) : value = input.toUtc() {
    if (value.year < 1 || value.year > 9999) {
      throw const FormatException('Instant outside supported range.');
    }
  }
  factory UtcInstant.parse(String text) {
    final match = RegExp(
      r'^([0-9]{4}-[0-9]{2}-[0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2})(\.[0-9]{1,6})?Z$',
    ).firstMatch(text);
    if (match == null) {
      throw const FormatException('Expected an ISO UTC instant.');
    }
    BusinessDate.parse(match[1]!);
    if (int.parse(match[2]!) > 23 ||
        int.parse(match[3]!) > 59 ||
        int.parse(match[4]!) > 59) {
      throw const FormatException('Invalid clock time.');
    }
    return UtcInstant(DateTime.parse(text));
  }
  final DateTime value;
  @override
  String toString() => value.toIso8601String();
  @override
  int compareTo(UtcInstant other) => value.compareTo(other.value);
  @override
  bool operator ==(Object other) => other is UtcInstant && value == other.value;
  @override
  int get hashCode => value.hashCode;
}
