import '../ledger/ledger.dart';
import '../formatting/figures.dart';

/// How [total] paid in [count] instalments is written, each amount as
/// [money] writes it: 「3 期 · 每期 3,000」, or when it does not divide
/// evenly, with the remainder where the bank puts it, 「3 期 · 首期 3,335，
/// 其後每期 3,333」.
String installmentPlan(
  int total,
  int count, {
  String Function(int amount) money = groupDigits,
}) {
  final amounts = installmentAmounts(total, count);
  final (first, rest) = (amounts.first, amounts.last);
  return first == rest
      ? '$count 期 · 每期 ${money(rest)}'
      : '$count 期 · 首期 ${money(first)}，其後每期 ${money(rest)}';
}
