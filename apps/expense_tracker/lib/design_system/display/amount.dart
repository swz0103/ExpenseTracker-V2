/// How every amount, count, price and percentage is written for people,
/// and how an amount is read out. The only place that turns a number into
/// what the user sees; the figures themselves come from
/// `package:core/money` and `package:core/percent`.
library;

import 'package:core/foundation_values.dart' show Currency;
import 'package:core/money/amount_format.dart';
import 'package:core/percent/percent.dart';

export 'package:core/money/amount_format.dart' show groupDigits;

/// The home currency, whose amounts are written without a code.
const _home = 'TWD';

/// What a currency is called beside its figures: NT\$ for New Taiwan
/// dollars, the code for the others, such as `USD`.
String currencyLabel(String currency) => currency == _home ? r'NT$' : currency;

/// What a currency is called aloud: 美元 for USD. The code itself for one
/// the app does not name.
String currencyName(String currency) => _names[currency] ?? currency;

const _names = {
  'TWD': '新台幣',
  'USD': '美元',
  'JPY': '日圓',
  'EUR': '歐元',
  'CNY': '人民幣',
  'HKD': '港幣',
  'KRW': '韓圓',
  'GBP': '英鎊',
  'AUD': '澳幣',
  'CAD': '加幣',
  'SGD': '新加坡幣',
  'CHF': '瑞士法郎',
  'NZD': '紐西蘭幣',
  'THB': '泰銖',
};

/// [minor] units of [currency] as typed into a field, without grouping:
/// `1234.50` for 123450 US cents, `300` for 300 NT\$.
String plainIn(int minor, String currency) =>
    figures(minor, Currency.scaleOf(currency), grouped: false);

/// [minor] units of [currency] as figures only, grouped and with its
/// decimals but without its code, for a place that shows the currency
/// beside them: `1,234.50` for 123450 US cents.
String figuresIn(int minor, String currency) =>
    figures(minor, Currency.scaleOf(currency));

/// [minor] units of [currency] as people write them: NT\$ as [groupDigits],
/// others with their code and decimals, such as `USD 1,234.50`.
String amountIn(int minor, String currency) => currency == _home
    ? groupDigits(minor)
    : '$currency ${figuresIn(minor, currency)}';

/// [minor] units with [scale] decimals as the amount keys write them,
/// to go on typing: `1200` NT\$, `12` for 1200 US cents, `12.50` for 1250.
String keyedAmount(int minor, int scale) {
  final text = figures(minor, scale, grouped: false);
  final zeros = '.${'0' * scale}';
  return scale > 0 && text.endsWith(zeros)
      ? text.substring(0, text.length - zeros.length)
      : text;
}

/// A sum on the amount keys as it comes to, [minor] units with [scale]
/// decimals: grouped whole units (`1,234`), or as typed with decimals
/// (`1234.50`, `12`).
String keyedResult(int minor, int scale) =>
    scale == 0 ? groupDigits(minor) : keyedAmount(minor, scale);

/// `1200` → `+1,200`, `-80` → `−80` (a true minus sign), `0` → `0`.
String signed(int value) => value > 0
    ? '+${groupDigits(value)}'
    : value < 0
    ? '−${groupDigits(-value)}'
    : '0';

/// An amount written with the sign of its direction: spending `−200`.
String spent(int value) => '−${groupDigits(value)}';

/// Axis labels in 萬 with one decimal: `52000` → `5.2`.
String tenThousands(int value) =>
    figures(divideRounded(value, 1000), 1, grouped: false);

/// Short amounts: `8500` → `8,500`, `125000` → `12.5萬`.
String shortAmount(int value) {
  if (value.abs() < 100000) return groupDigits(value);
  final text = tenThousands(value);
  return '${text.endsWith('.0') ? text.substring(0, text.length - 2) : text}萬';
}

/// A count with its unit, grouped: `8,177 筆`, `21,000 股`, `1,780 天`.
String countOf(int count, String unit) => '${groupDigits(count)} $unit';

/// A share price with up to two decimals, trailing zeros trimmed and
/// grouped: `128.5`, `1,045`, `23.45`. Never rounds away a real tick.
String stockPrice(double price) => trimmedDecimals(price, 2);

/// A price on a chart's axis, a tick rather than a close: one decimal
/// under 100 (`23.5`), whole above (`129`).
String priceTick(double price) => fixedDecimals(price, price < 100 ? 1 : 0);

/// A count on a chart's axis: `850`, `1.5k` for 1,500.
String countTick(int count) => count >= 1000
    ? '${figures(divideRounded(count, 100), 1, grouped: false)}k'
    : '$count';

/// A share price as typed into a field: `128.5`, `194.35`, `600`.
String plainPrice(double price) => trimmedDecimals(price, 2, grouped: false);

/// A change of a share price with exactly two decimals and no sign:
/// `0.50`, `12.00`.
String priceMove(double move) => fixedDecimals(move.abs(), 2, grouped: true);

/// A percent in tenths (from `percentTenths`) with one decimal and a `%`:
/// `12.5%`, `-0.9%`; with [sign], `+12.5%` for a rise.
String tenthsPercent(int tenths, {bool sign = false}) =>
    '${sign && tenths > 0 ? '+' : ''}${figures(tenths, 1)}%';

/// [part] of [whole] as a signed percentage with one decimal: `+12.5%`,
/// `-4.0%`; `0%` when [whole] is 0.
String percentOf(int part, int whole) =>
    whole == 0 ? '0%' : tenthsPercent(percentTenths(part, whole), sign: true);

/// A ratio held as a double (0.125 for 12.5%) as a signed percentage
/// with one decimal: `+12.5%`.
String ratioPercent(double ratio) =>
    tenthsPercent(ratioTenths(ratio), sign: true);

/// [part] of [whole] as a whole percent: `33%`. `0%` when [whole] is 0.
String wholePercent(int part, int whole) => '${percent(part, whole)}%';

/// What an amount says by its sign, for reading it out.
enum AmountSense {
  /// Money out, written `−200`: read 支出.
  spending,

  /// Money in, written `+200`: read 收入.
  income,

  /// A rise or a fall, written `+200` or `−200`: read 正 or 負.
  signed,

  /// An amount with no direction, such as a balance or a transfer: read
  /// as it is, 負 only when below zero.
  plain,
}

/// What a screen reader says for an amount: the direction in words and
/// the size with its currency, never a sign character. `支出 1,844 元`,
/// `收入 25,000 元`, `美元 12.50`, `負 300 元`; `支出 金額已隱藏` while
/// amounts are hidden. [minor] keeps its sign; for [AmountSense.spending]
/// and [AmountSense.income] only its size counts.
String spokenAmount(
  int minor, {
  String currency = _home,
  AmountSense sense = AmountSense.plain,
  bool hidden = false,
}) {
  final direction = switch (sense) {
    AmountSense.spending => '支出',
    AmountSense.income => '收入',
    AmountSense.signed when minor > 0 => '正',
    AmountSense.signed || AmountSense.plain when minor < 0 => '負',
    _ => '',
  };
  final size = hidden
      ? '金額已隱藏'
      : currency == _home
      ? '${groupDigits(minor.abs())} 元'
      : '${currencyName(currency)} ${figuresIn(minor.abs(), currency)}';
  return direction.isEmpty ? size : '$direction $size';
}

/// An amount as it is written beside [spokenAmount]: `−1,844`, `+25,000`,
/// `USD 12.50`, `−USD 3.00`; `••••` while [hidden].
String shownAmount(
  int minor, {
  String currency = _home,
  AmountSense sense = AmountSense.plain,
  bool hidden = false,
}) {
  if (hidden) return '••••';
  final size = amountIn(minor.abs(), currency);
  return switch (sense) {
    AmountSense.spending => '−$size',
    AmountSense.income => '+$size',
    AmountSense.signed when minor > 0 => '+$size',
    AmountSense.signed when minor < 0 => '−$size',
    AmountSense.plain when minor < 0 => amountIn(minor, currency),
    _ => size,
  };
}
