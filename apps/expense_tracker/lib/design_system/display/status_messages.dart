/// The words of every status, kept together: the only place they are
/// written (rule B7). `status.dart` pairs each with its colour, glyph and
/// spoken label; plain Dart, so models can use the words too.
library;

/// The words of the statuses.
abstract final class StatusWords {
  static const notBilled = '未出帳';
  static const billed = '已出帳';
  static const dueTodayCard = '今天繳款';
  static const overdue = '已逾期';
  static const paid = '已繳清';
  static const left = '剩';
  static const near = '快用完';
  static const over = '超支';
  static const held = '持有中';
  static const soldOut = '已賣光';
  static const upcoming = '未到期';
  static const due = '到期';
  static const booked = '已入帳';
  static const skipped = '已略過';
  static const paused = '已暫停';
  static const open = '未收回';
  static const partlySettled = '部分收回';
  static const settled = '已結清';
}
