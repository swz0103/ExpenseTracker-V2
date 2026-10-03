import 'package:foundation_values/foundation_values.dart';

/// `1234567.8` → `1,234,567.80`, with the currency's own decimals.
String formatMoney(Money money) {
  final text = money.majorText;
  final negative = text.startsWith('-');
  final unsigned = negative ? text.substring(1) : text;
  final dot = unsigned.indexOf('.');
  final whole = dot < 0 ? unsigned : unsigned.substring(0, dot);
  final fraction = dot < 0 ? '' : unsigned.substring(dot);
  final grouped = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) grouped.write(',');
    grouped.write(whole[i]);
  }
  return '${negative ? '-' : ''}$grouped$fraction';
}

String formatDate(BusinessDate date) =>
    '${date.year}/${date.month}/${date.day}';

/// Reads an amount typed by a person. Commas are allowed; extra decimals
/// are refused rather than rounded.
Money parseAmount(Currency currency, String text) =>
    Money.parse(currency, text.replaceAll(',', '').trim());
