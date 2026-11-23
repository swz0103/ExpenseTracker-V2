library;

/// Dates as the app writes them and groups by, each in one place. The
/// formats are named for the ICU (CLDR) date skeletons, as `intl`'s
/// `DateFormat.Md()` and its kin are: M month, d day, y year, E weekday,
/// MMM the month in words.

/// The days of the week in its order, from Sunday as Taiwan's calendars
/// print it, as 週 is followed by them.
const weekdayNames = ['日', '一', '二', '三', '四', '五', '六'];

/// [d]'s place in the week: 0 for Sunday to 6 for Saturday.
int weekdayIndex(DateTime d) => d.weekday % DateTime.daysPerWeek;

/// [DateTime.weekday] of the day at [index] in the week, from Sunday:
/// DateTime numbers Sunday 7, the week here starts on it as 0.
int weekdayAt(int index) => index == 0 ? DateTime.sunday : index;

/// The Sunday the week of [d] starts on.
DateTime startOfWeek(DateTime d) => d.subtract(Duration(days: weekdayIndex(d)));

/// 「週日」.
String formatE(DateTime d) => '週${weekdayNames[weekdayIndex(d)]}';

/// 「10/4」.
String formatMd(DateTime d) => '${d.month}/${d.day}';

/// 「10/4 週日」.
String formatMEd(DateTime d) => '${formatMd(d)} ${formatE(d)}';

/// 「2026/10/4」.
String formatYMd(DateTime d) => '${d.year}/${d.month}/${d.day}';

/// 「09:05」.
String formatHm(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:'
    '${d.minute.toString().padLeft(2, '0')}';

/// 「2026/10/4 09:05」.
String formatYMdHm(DateTime d) => '${formatYMd(d)} ${formatHm(d)}';

/// 「2026/10」.
String formatYM(DateTime d) => '${d.year}/${d.month}';

/// 「10 月 4 日」.
String formatMMMd(DateTime d) => '${d.month} 月 ${d.day} 日';

/// 「2026 年 10 月」.
String formatYMMM(DateTime d) => '${d.year} 年 ${d.month} 月';

/// 「10 月 4 日 · 週日」.
String formatMMMEd(DateTime d) => '${formatMMMd(d)} · ${formatE(d)}';

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
    days.putIfAbsent(DateTime.utc(d.year, d.month, d.day), () => []).add(item);
  }
  return days;
}
