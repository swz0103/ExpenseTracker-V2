import '../formatting/setting_topic.dart';

import 'package:ledger_trade_costs/calc/charges.dart' show fullFeePerMillion;

import '../../../design_system/display/amount.dart' show perMillionPercent;
import '../formatting/words.dart';

/// The words of the setting 券商手續費折扣: the broker's discount a trade's
/// fee is suggested at.
abstract final class BrokerDiscountText {
  static const title = '券商手續費折扣';

  /// What it changes, under the choices: the full fee's rate as the fee
  /// is worked out at.
  static final detail =
      '記買進、賣出時試算的手續費：成交金額 × ${perMillionPercent(fullFeePerMillion)} × 折扣；帳戶可另設自己的折扣';

  /// The field of an account's own discount, and what it says empty: the
  /// two ways of writing one, as the same discount (D86).
  static const accountHint = '例如 6 折或 0.6；空白沿用設定的預設折扣';

  /// A discount typed that is a number, but none a fee is charged at.
  static const outOfRange = '折扣要大於 0、最多 1（不打折），例如 6 折或 0.6';

  /// A discount typed that is not read as one, such as 0.6 折, which
  /// mixes the two ways of writing it (D86).
  static const unreadable = '看不懂這個折扣，請寫成 6 折或 0.6';

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

/// What search finds in AppearanceSection (N8): each setting's name and the other
/// words a person may type for it, marking the card that section builds.
abstract final class AppearanceTopics {
  static const look = SettingTopic('外觀', words: ['深色', '淺色', '主題']);

  static const vibration = SettingTopic('震動', words: ['觸感']);

  static const homeWidget = SettingTopic('桌面小工具', words: ['小工具', '桌面']);

  static const blocks = SettingTopic('總覽區塊', words: ['排序', '隱藏']);

  static const discount = SettingTopic(
    BrokerDiscountText.title,
    words: BrokerDiscountText.searchWords,
  );
}
