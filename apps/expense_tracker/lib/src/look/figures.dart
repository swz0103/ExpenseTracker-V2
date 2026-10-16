/// `1234567` → `1,234,567`; negatives keep a plain `-`.
String groupDigits(int value) {
  final digits = value.abs().toString();
  final grouped = StringBuffer(value < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) grouped.write(',');
    grouped.write(digits[i]);
  }
  return grouped.toString();
}

/// `1200` → `+1,200`, `-80` → `−80` (a true minus sign), `0` → `0`.
String signed(int value) => value > 0
    ? '+${groupDigits(value)}'
    : value < 0
    ? '−${groupDigits(-value)}'
    : '0';

/// An amount written with the sign of its direction: spending `−200`.
String spent(int value) => '−${groupDigits(value)}';

/// Axis labels in 萬 with one decimal: `52000` → `5.2`.
String tenThousands(int value) => (value / 10000).toStringAsFixed(1);

/// Short amounts: `8500` → `8,500`, `125000` → `12.5萬`.
String shortAmount(int value) {
  if (value.abs() < 100000) return groupDigits(value);
  final text = (value / 10000).toStringAsFixed(1);
  return '${text.endsWith('.0') ? text.substring(0, text.length - 2) : text}萬';
}

/// [part] of [whole] as a signed percentage with one decimal.
String percentOf(int part, int whole) {
  if (whole == 0) return '0%';
  final value = part * 100 / whole;
  return '${value > 0 ? '+' : ''}${value.toStringAsFixed(1)}%';
}

const weekdayNames = ['一', '二', '三', '四', '五', '六', '日'];

/// 「10 月 4 日 · 週日」.
String longDay(DateTime date) =>
    '${date.month} 月 ${date.day} 日 · 週${weekdayNames[date.weekday - 1]}';

/// 「2026 年 10 月 4 日 · 週日」.
String fullDay(DateTime date) => '${date.year} 年 ${longDay(date)}';

/// While true, [money] and [moneySigned] write dots instead of amounts:
/// the 隱藏金額 switch, set by the ledger.
bool amountsHidden = false;

/// [groupDigits], or dots while amounts are hidden.
String money(int value) => amountsHidden ? '••••' : groupDigits(value);

/// [signed], or dots while amounts are hidden.
String moneySigned(int value) => amountsHidden ? '••••' : signed(value);
