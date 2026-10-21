import 'dart:math';

/// How long a report runs.
enum ReportSpan { month, quarter, year, custom }

/// One stretch of a period, as the charts draw it: its label and first
/// and last day.
typedef ReportStretch = (String, DateTime, DateTime);

/// The time a report covers: a month, a quarter, a year, or a run of
/// months the person chose. Two periods over the same months are equal,
/// so the sums worked out for one can be kept for the other.
final class ReportPeriod {
  const ReportPeriod(this.span, this.start, this.end);

  /// The [span] that holds [today]; a chosen range starts as the twelve
  /// months up to it.
  factory ReportPeriod.of(ReportSpan span, DateTime today) => ReportPeriod(
    span,
    switch (span) {
      ReportSpan.month => DateTime.utc(today.year, today.month),
      ReportSpan.quarter => DateTime.utc(
        today.year,
        (today.month - 1) ~/ 3 * 3 + 1,
      ),
      ReportSpan.year => DateTime.utc(today.year),
      ReportSpan.custom => DateTime.utc(today.year, today.month - 11),
    },
    DateTime.utc(today.year, today.month),
  );

  /// The months from [first] to [last], whatever days were picked in them.
  factory ReportPeriod.range(DateTime first, DateTime last) => ReportPeriod(
    ReportSpan.custom,
    DateTime.utc(first.year, first.month),
    DateTime.utc(last.year, last.month),
  );

  final ReportSpan span;

  /// The first month.
  final DateTime start;

  /// The last month of a chosen range; kept alongside the other spans.
  final DateTime end;

  static DateTime lastDay(DateTime month) =>
      DateTime.utc(month.year, month.month + 1, 0);

  int get months => switch (span) {
    ReportSpan.month => 1,
    ReportSpan.quarter => 3,
    ReportSpan.year => 12,
    ReportSpan.custom =>
      (end.year - start.year) * 12 + end.month - start.month + 1,
  };

  /// The first and last day.
  DateTime get from => start;
  DateTime get to => lastDay(DateTime.utc(start.year, start.month + months - 1));

  /// The first month after the period.
  DateTime get next => DateTime.utc(start.year, start.month + months);

  /// The same length of time just before (a negative [by]) or after.
  ReportPeriod step(int by) => ReportPeriod(
    span,
    DateTime.utc(start.year, start.month + by * months),
    DateTime.utc(end.year, end.month + by * months),
  );

  String get title {
    final y = start.year;
    return switch (span) {
      ReportSpan.month => '$y 年 ${start.month} 月',
      ReportSpan.quarter => '$y 年 第 ${(start.month - 1) ~/ 3 + 1} 季',
      ReportSpan.year => '$y 年',
      ReportSpan.custom => '$y/${start.month} – ${end.year}/${end.month}',
    };
  }

  /// The stretches the charts are drawn by: weeks of a month, months of
  /// anything longer.
  List<ReportStretch> get stretches {
    if (span == ReportSpan.month) {
      final last = lastDay(start).day;
      return [
        for (var day = 1; day <= last; day += 7)
          (
            '$day 日',
            DateTime.utc(start.year, start.month, day),
            DateTime.utc(start.year, start.month, min(day + 6, last)),
          ),
      ];
    }
    return [
      for (var i = 0; i < months; i++)
        (
          span == ReportSpan.year
              ? '${i + 1}'
              : '${DateTime.utc(start.year, start.month + i).month}月',
          DateTime.utc(start.year, start.month + i),
          lastDay(DateTime.utc(start.year, start.month + i)),
        ),
    ];
  }

  @override
  bool operator ==(Object other) =>
      other is ReportPeriod &&
      other.span == span &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(span, start, end);
}
