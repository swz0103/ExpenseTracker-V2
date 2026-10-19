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

/// Which days banks and the stock exchange are open: weekdays, except
/// [holidays], plus weekend [workdays] that make up for a holiday.
/// Taiwan's calendar is published yearly, so it is supplied, not built in
/// (feature audit G-07, G-10).
final class BankingCalendar {
  BankingCalendar({
    Set<BusinessDate> holidays = const {},
    Set<BusinessDate> workdays = const {},
  }) : holidays = Set.unmodifiable(holidays),
       workdays = Set.unmodifiable(workdays);

  final Set<BusinessDate> holidays;
  final Set<BusinessDate> workdays;

  bool isOpen(BusinessDate date) {
    if (workdays.contains(date)) return true;
    final weekday = DateTime.utc(date.year, date.month, date.day).weekday;
    return weekday != DateTime.saturday &&
        weekday != DateTime.sunday &&
        !holidays.contains(date);
  }

  /// [date] when open, otherwise the next open day.
  BusinessDate onOrAfter(BusinessDate date) {
    var day = date;
    for (var i = 0; i < 60; i++) {
      if (isOpen(day)) return day;
      day = _next(day);
    }
    throw StateError('No open day within 60 days of $date.');
  }

  /// The [count]th open day after [date], as in T+2 settlement.
  BusinessDate addOpenDays(BusinessDate date, int count) {
    if (count < 0) throw ArgumentError.value(count, 'count');
    var day = date;
    for (var left = count; left > 0;) {
      day = onOrAfter(_next(day));
      left--;
    }
    return day;
  }

  static BusinessDate _next(BusinessDate date) {
    final next = DateTime.utc(date.year, date.month, date.day + 1);
    return BusinessDate(next.year, next.month, next.day);
  }
}
