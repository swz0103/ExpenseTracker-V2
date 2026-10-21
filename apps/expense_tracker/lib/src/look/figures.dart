import 'package:core/foundation_values.dart' show Currency;

import '../model/amounts.dart';
import '../model/ledger.dart' show Ledger;

export '../model/amounts.dart';

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

/// [minor] units of [currency] as people write them: NT$ as [groupDigits],
/// others with their code and decimals, such as `USD 1,234.50`.
String amountIn(int minor, String currency) {
  if (currency == 'TWD') return groupDigits(minor);
  if (Currency.scaleOf(currency) == 0) {
    return '$currency ${groupDigits(minor)}';
  }
  final cents = (minor.abs() % 100).toString().padLeft(2, '0');
  final whole = groupDigits(minor.abs() ~/ 100);
  return '$currency ${minor < 0 ? '-' : ''}$whole.$cents';
}

/// Amounts as a ledger shows them: dots in place of every figure while
/// its 隱藏金額 switch is on. Each screen asks its own ledger, so two books
/// open at once (as in tests) never share the switch.
extension ShownAmounts on Ledger {
  /// [text], or dots while amounts are hidden.
  String orDots(String text) => hidden ? '••••' : text;

  /// [groupDigits], or dots while amounts are hidden.
  String money(int value) => orDots(groupDigits(value));

  /// [signed], or dots while amounts are hidden.
  String moneySigned(int value) => orDots(signed(value));

  /// [amountIn], or dots while amounts are hidden.
  String moneyIn(int minor, String currency) =>
      orDots(amountIn(minor, currency));
}
