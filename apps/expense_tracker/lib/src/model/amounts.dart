import 'package:foundation_values/foundation_values.dart' show Currency;

/// [minor] units of [currency] as typed into a field, without grouping:
/// `1234.50` for 123450 US cents.
String plainIn(int minor, String currency) {
  if (Currency.scaleOf(currency) == 0) return '$minor';
  final cents = (minor.abs() % 100).toString().padLeft(2, '0');
  return '${minor < 0 ? '-' : ''}${minor.abs() ~/ 100}.$cents';
}

/// What [text] says in the smallest unit of [currency]: `12.5` USD →
/// 1250, `-300` NT$ → -300. Null for anything else, such as more
/// decimals than the currency has.
int? minorOf(String text, String currency) {
  final cleaned = text.replaceAll(',', '').trim();
  final match = RegExp(r'^(-?)(\d+)(?:\.(\d*))?$').firstMatch(cleaned);
  if (match == null) return null;
  final scale = Currency.scaleOf(currency);
  final decimals = match[3] ?? '';
  if (decimals.length > scale) return null;
  final whole = int.parse(match[2]!);
  final value = scale == 0
      ? whole
      : whole * 100 + int.parse(decimals.padRight(2, '0'));
  return match[1]!.isEmpty ? value : -value;
}

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
