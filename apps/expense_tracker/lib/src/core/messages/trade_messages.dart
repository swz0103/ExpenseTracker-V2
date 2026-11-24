import '../formatting/words.dart';

/// The words of the setting 券商手續費折扣: the broker's discount a trade's
/// fee is suggested at.
abstract final class BrokerDiscountText {
  static const title = '券商手續費折扣';

  /// What it changes, under the choices.
  static const detail = '記買進、賣出時試算的手續費：成交金額 × 0.1425% × 折扣；帳戶可另設自己的折扣';

  /// The field of an account's own discount, and what it says empty.
  static const accountHint = '例如 0.6 或 2.8 折；空白沿用設定的預設折扣';

  /// A discount typed that is a number, but none a fee is charged at.
  static const outOfRange = '折扣要大於 0、最多 1（不打折），例如 0.6 或 6 折';

  /// A discount typed that is not a number.
  static const unreadable = '請輸入折扣，例如 0.6 或 2.8 折';

  /// Other words it is found by in the settings' search.
  static const searchWords = [Words.fee, '折扣', '券商', '股票'];

  /// The discounts offered, in basis points of the full fee, as rows of
  /// choices: none, 6折, 5折; 3.8折, 2.8折, 2折.
  static const rows = [
    [10000, 6000, 5000],
    [3800, 2800, 2000],
  ];
}

/// A discount in basis points of the full fee as a broker writes it:
/// 6000 as 「6 折」, 2800 as 「2.8 折」, 10000 as 「不打折」.
String discountName(int basisPoints) {
  if (basisPoints >= 10000) return '不打折';
  final whole = basisPoints ~/ 1000;
  // The rest in thousandths of a 折, written without trailing zeros.
  var rest = basisPoints % 1000;
  final digits = StringBuffer();
  for (var unit = 100; rest > 0; unit ~/= 10) {
    digits.write(rest ~/ unit);
    rest %= unit;
  }
  return digits.isEmpty ? '$whole 折' : '$whole.$digits 折';
}

/// A discount in basis points of the full fee as it is typed: 6000 as
/// 0.6, 2850 as 0.285, 10000 as 1; empty for none.
String discountTyped(int? basisPoints) {
  if (basisPoints == null) return '';
  if (basisPoints >= 10000) return '1';
  final digits = basisPoints
      .toString()
      .padLeft(4, '0')
      .replaceFirst(RegExp(r'0+$'), '');
  return '0.$digits';
}
