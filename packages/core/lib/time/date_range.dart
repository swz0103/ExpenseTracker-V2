import 'calendar_day.dart';

/// The days from [first] to [last], both included.
final class DateRange {
  DateRange(this.first, this.last) {
    if (last.isBefore(first)) {
      throw ArgumentError('A range cannot end before it starts.');
    }
  }

  final BusinessDate first;
  final BusinessDate last;

  /// How many days it covers, both ends counted.
  int get days => first.daysUntil(last) + 1;

  bool contains(BusinessDate date) =>
      !date.isBefore(first) && !date.isAfter(last);

  @override
  bool operator ==(Object other) =>
      other is DateRange && other.first == first && other.last == last;

  @override
  int get hashCode => Object.hash(first, last);

  @override
  String toString() => '$first..$last';
}
