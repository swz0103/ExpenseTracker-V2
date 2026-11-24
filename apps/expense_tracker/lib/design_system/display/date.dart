library;

import 'package:core/foundation_values.dart' as time;

import '../../src/core/formatting/words.dart';

import 'package:core/time/utc_days.dart';

/// Dates as the app shows them to people, each in one place. The formats
/// are named for the ICU (CLDR) date skeletons, as `intl`'s
/// `DateFormat.Md()` and its kin are: M month, d day, y year, E weekday,
/// MMM the month in words, Hm hours and minutes. The calendar itself
/// (weeks, months, business days) is core's `time`.

/// The days of the week in its order, from Sunday as Taiwan's calendars
/// print it, as 週 is followed by them.
const weekdayNames = ['日', '一', '二', '三', '四', '五', '六'];

/// [d]'s place in the week: 0 for Sunday to 6 for Saturday.
int weekdayIndex(DateTime d) => time.weekdayIndex(time.BusinessDate.of(d));

/// [DateTime.weekday] of the day at [index] in the week, from Sunday.
int weekdayAt(int index) => time.weekdayAt(index);

/// The day the week of [d] starts on, at [d]'s time of day.
DateTime startOfWeek(DateTime d) => d.subtract(Duration(days: weekdayIndex(d)));

/// 「週日」.
String formatE(DateTime d) => '週${weekdayNames[weekdayIndex(d)]}';

/// 「10/4」.
String formatMd(DateTime d) => '${d.month}/${d.day}';

/// 「10/4 週日」.
String formatMEd(DateTime d) => '${formatMd(d)} ${formatE(d)}';

/// 「2026/10/4」.
String formatYMd(DateTime d) => '${d.year}/${d.month}/${d.day}';

/// 「2026/10」.
String formatYM(DateTime d) => '${d.year}/${d.month}';

/// 「10 月 4 日」.
String formatMMMd(DateTime d) => '${d.month} 月 ${d.day} 日';

/// 「2026 年 10 月」.
String formatYMMM(DateTime d) => '${d.year} 年 ${d.month} 月';

/// 「10 月 4 日 · 週日」.
String formatMMMEd(DateTime d) => '${formatMMMd(d)} · ${formatE(d)}';

/// 「09:05」.
String formatHm(int hour, int minute) =>
    '${time.twoDigits(hour)}:${time.twoDigits(minute)}';

/// 「09 : 05」, spaced for a time shown large.
String formatHmSpaced(int hour, int minute) =>
    '${time.twoDigits(hour)} : ${time.twoDigits(minute)}';

/// 「09」: an hour or a minute alone, as a time picker lists them.
String formatTimeField(int value) => time.twoDigits(value);

/// 「2026/10/4 09:05」.
String formatYMdHm(DateTime d) =>
    '${formatYMd(d)} ${formatHm(d.hour, d.minute)}';

/// 「10/4」 in [today]'s year, 「2025/10/4」 in any other.
String formatDay(DateTime d, {required DateTime today}) =>
    d.year == today.year ? formatMd(d) : formatYMd(d);

/// 「1/8 – 11/22」 within [today]'s year; with the years on both ends
/// when the range is in another year or runs across years.
String formatDayRange(DateTime from, DateTime to, {required DateTime today}) =>
    from.year == today.year && to.year == today.year
    ? '${formatMd(from)} – ${formatMd(to)}'
    : '${formatYMd(from)} – ${formatYMd(to)}';

/// 「本月」 for the month [today] is in; otherwise the month's own name:
/// 「9 月」 in the same year, 「2025 年 9 月」 in another.
String monthWord(int year, int month, {required DateTime today}) {
  if (year == today.year && month == today.month) return '本月';
  if (year == today.year) return '$month 月';
  return '$year 年 $month 月';
}

/// 「今天」, 「昨天」, or the day as [formatDay] writes it.
String relativeDay(DateTime d, {required DateTime today}) {
  final day = dayOf(d);
  final days = dayOf(today).difference(day).inDays;
  if (days == 0) return Words.today;
  if (days == 1) return '昨天';
  return formatDay(d, today: today);
}

/// What a day's market change is labelled by: 「今日」 when [quoteDay],
/// the trading day of the close, is [today]; otherwise that day, as on a
/// weekend or a holiday (「10/9」).
String tradingDayWord(DateTime quoteDay, {required DateTime today}) =>
    dayOf(quoteDay) == dayOf(today) ? '今日' : formatDay(quoteDay, today: today);

/// 「今天 21:03」, 「昨天 08:14」 or 「11/2 08:14」: when something
/// happened, for a list of recent events.
String formatWhen(DateTime at, {required DateTime today}) =>
    '${relativeDay(at, today: today)} ${formatHm(at.hour, at.minute)}';

/// 「順延至 10/12」 when a due day [due] moves to [payBy], the next
/// business day; with 「（未含國定假日）」 when [payBy]'s year is not in
/// the holiday table and only weekends were skipped. Null when it does
/// not move.
String? postponedTo(
  DateTime due,
  time.BusinessDayAnswer<time.BusinessDate> payBy,
) {
  final day = payBy.value.asUtcMidnight;
  if (day == dayOf(due)) return null;
  return '順延至 ${formatMd(day)}${_weekendsOnlyNote(payBy)}';
}

/// 「10/12」, the day a trade settles; with 「（未含國定假日）」 when its
/// year is not in the holiday tables and only weekends were skipped.
String settlesOn(time.BusinessDayAnswer<time.BusinessDate> settles) =>
    '${formatMd(settles.value.asUtcMidnight)}${_weekendsOnlyNote(settles)}';

/// What a day counted without the holidays of its year is followed by.
String _weekendsOnlyNote(time.BusinessDayAnswer<Object> answer) =>
    answer is time.WeekendsOnly ? '（未含國定假日）' : '';

/// [items] grouped by the day [dateOf] gives each, the time of day left
/// out: the days in the order first met, each with its items in their
/// order.
Map<DateTime, List<T>> groupByDay<T>(
  Iterable<T> items,
  DateTime Function(T item) dateOf,
) {
  final days = <DateTime, List<T>>{};
  for (final item in items) {
    final d = dateOf(item);
    days.putIfAbsent(dayOf(d), () => []).add(item);
  }
  return days;
}
