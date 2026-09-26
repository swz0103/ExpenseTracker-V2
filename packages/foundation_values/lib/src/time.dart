/// A civil calendar date with no timezone or implied midnight instant.
final class BusinessDate implements Comparable<BusinessDate> {
  BusinessDate(this.year, this.month, this.day) {
    if (year < 1 ||
        year > 9999 ||
        month < 1 ||
        month > 12 ||
        day < 1 ||
        day > 31) {
      throw const FormatException('Invalid business date.');
    }
    final checked = DateTime.utc(year, month, day);
    if (checked.year != year || checked.month != month || checked.day != day) {
      throw const FormatException('Invalid business date.');
    }
  }
  factory BusinessDate.parse(String text) {
    if (!RegExp(r'^[0-9]{4}-[0-9]{2}-[0-9]{2}$').hasMatch(text)) {
      throw const FormatException('Expected YYYY-MM-DD.');
    }
    return BusinessDate(
      int.parse(text.substring(0, 4)),
      int.parse(text.substring(5, 7)),
      int.parse(text.substring(8, 10)),
    );
  }
  final int year;
  final int month;
  final int day;
  @override
  String toString() =>
      '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
  @override
  int compareTo(BusinessDate other) => toString().compareTo(other.toString());
  @override
  bool operator ==(Object other) =>
      other is BusinessDate &&
      year == other.year &&
      month == other.month &&
      day == other.day;
  @override
  int get hashCode => Object.hash(year, month, day);
}

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
    if (match == null)
      throw const FormatException('Expected an ISO UTC instant.');
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
