library;

/// Dates as the app writes them, each in one place. The names are the
/// ICU (CLDR) date skeletons, as `intl`'s `DateFormat.Md()` and its kin
/// use: M month, d day, y year, E weekday, MMM the month in words.

/// The days of the week from Monday, as 週 is followed by them.
const weekdayNames = ['一', '二', '三', '四', '五', '六', '日'];

/// 「週日」.
String formatE(DateTime d) => '週${weekdayNames[d.weekday - 1]}';

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
