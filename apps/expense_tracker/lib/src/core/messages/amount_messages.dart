import 'package:core/money/amount_parser.dart';
import 'package:domain/investments.dart' show doubtfulMoveKeptDays;

import '../../../design_system/display/amount.dart';
import '../../../design_system/display/date.dart' show formatDay;

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

/// Why what was typed into an amount field is not an amount, said under
/// the field; null when it is one or the field is left empty.
String? typedProblem(AmountResult typed) => switch (typed) {
  AmountOk() || AmountRefused(problem: AmountProblem.empty) => null,
  AmountRefused(:final problem) => amountProblemMessage(problem),
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

/// Under a foreign amount's worth in NT$ on a day gone by, worked out at
/// today's [rate] until typed: an estimate, as no board of that day or
/// before it is kept (R5, D58). The rate is written by [exchangeRate]: 32, not 32.0 (D118).
String estimatedAtTodaysRate(double rate) =>
    '以今日臺銀即期買入 ${exchangeRate(rate)} 估算，請改成當日金額';

/// Why a day gone by is valued at today's rate though a board before it
/// is kept: the nearest is more than [doubtfulMoveKeptDays] older (D123).
const boardTooOldWords = '最近的牌價早於當日 $doubtfulMoveKeptDays 天以上，不採用';

/// Under a foreign amount's worth in NT$ on a day gone by whose nearest
/// earlier board is too old to take (D123): [estimatedAtTodaysRate], with
/// why.
String estimatedPastOldBoard(double rate) =>
    '$boardTooOldWords；${estimatedAtTodaysRate(rate)}';

/// Under a foreign amount's worth in NT$ today: the [rate] it is worked
/// out at, written by [exchangeRate].
String todaysRate(double rate) => '臺銀即期買入 ${exchangeRate(rate)}';

/// Under a foreign amount's worth in NT$: the [rate] of the board of
/// [day] it is worked out at, that day's or the nearest earlier one kept
/// (D58), its day named as [formatDay] writes it next to [today].
String rateOfDay(double rate, DateTime day, {required DateTime today}) =>
    '臺銀 ${formatDay(day, today: today)} 即期買入 ${exchangeRate(rate)}';
