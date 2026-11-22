import 'package:core/money/amount_parser.dart';

import '../../../design_system/display/amount.dart';

/// What the person is told when what they typed or imported is not an
/// amount: every reason's words, in one place.
String amountProblemMessage(AmountProblem problem) => switch (problem) {
  AmountProblem.empty => '請輸入金額',
  AmountProblem.notANumber => '不是有效的金額',
  AmountProblem.tooManyDecimals => '小數位數比這個幣別多',
  AmountProblem.tooLarge => '金額不能超過 ${groupDigits(maxAmountUnits)}',
  AmountProblem.ambiguous => '看不出是哪個數字，請寫成 1,234.50 這樣',
  AmountProblem.divisionByZero => '不能除以 0',
  AmountProblem.negative => '金額不能小於 0',
};

/// Why a [column] of an imported line is left out: 金額看不懂：不是有效的金額.
String unreadableColumn(String column, AmountProblem problem) =>
    '$column看不懂：${amountProblemMessage(problem)}';

/// What a progress bar or ring is read as, before its percent, so a
/// screen reader never starts with a bare number.
abstract final class ProgressWords {
  static const cycleGone = '本期已過';
  static const limitUsed = '額度已用';
  static const instalmentsPaid = '分期已繳';
  static const used = '已用';
  static const repaid = '已還';
  static const downloading = '下載中';
}

/// A sign between figures read as a word: 減 for −, 加 for + or ＋.
String spokenSign(String sign) => sign == '−' ? '減' : '加';
