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
