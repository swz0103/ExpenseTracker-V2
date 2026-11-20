import 'package:core/foundation_values.dart' show Currency;

import 'amounts.dart';

export 'amounts.dart';

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

/// What a currency is called beside its figures: NT\$ for New Taiwan
/// dollars, the code for the others, such as `USD`.
String currencyLabel(String currency) => currency == 'TWD' ? r'NT$' : currency;

/// [minor] units of [currency] as figures only, grouped and with its
/// decimals but without its code, for a place that shows the currency
/// beside them: `1,234.50` for 123450 US cents.
String figuresIn(int minor, String currency) {
  if (Currency.scaleOf(currency) == 0) return groupDigits(minor);
  final cents = (minor.abs() % 100).toString().padLeft(2, '0');
  final whole = groupDigits(minor.abs() ~/ 100);
  return '${minor < 0 ? '-' : ''}$whole.$cents';
}

/// [minor] units of [currency] as people write them: NT\$ as [groupDigits],
/// others with their code and decimals, such as `USD 1,234.50`.
String amountIn(int minor, String currency) => currency == 'TWD'
    ? groupDigits(minor)
    : '$currency ${figuresIn(minor, currency)}';
