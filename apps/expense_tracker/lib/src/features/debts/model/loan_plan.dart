import 'dart:math' as math;

import '../../../core/ledger/records.dart';

/// What a loan costs as set: the first and last month's payment and the
/// interest over its whole term, in whole NT$.
typedef LoanPlan = ({int first, int last, int interest});

/// The plan for [amount] borrowed at [rate] (hundredths of a percent a
/// year) over [months], paid back by [repay]; null while something is
/// missing. A loan at no interest pays the same share each month.
LoanPlan? loanPlan({
  required int? amount,
  required int? rate,
  required int? months,
  required LoanRepay repay,
}) {
  if (amount == null || amount <= 0) return null;
  if (months == null || months <= 0) return null;
  final r = (rate ?? 0) / 10000 / 12;
  switch (repay) {
    case LoanRepay.interest:
      final each = (amount * r).round();
      return (first: each, last: each + amount, interest: each * months);
    case LoanRepay.principal:
      final share = amount / months;
      return (
        first: (share + amount * r).round(),
        last: (share + share * r).round(),
        interest: (amount * r * (months + 1) / 2).round(),
      );
    case LoanRepay.even:
      if (r == 0) {
        final each = (amount / months).round();
        return (first: each, last: each, interest: 0);
      }
      final each = amount * r / (1 - math.pow(1 + r, -months));
      return (
        first: each.round(),
        last: each.round(),
        interest: (each * months - amount).round(),
      );
  }
}

/// [LoanRepay] as the form names it.
String repayName(LoanRepay repay) => switch (repay) {
  LoanRepay.even => '本息平均',
  LoanRepay.principal => '本金平均',
  LoanRepay.interest => '只繳息',
};

/// A rate as typed, such as 「2.15」, in hundredths of a percent; null
/// when it is not a number from 0 to 100.
int? rateOf(String typed) {
  final value = double.tryParse(typed.trim());
  if (value == null || value < 0 || value > 100) return null;
  return (value * 100).round();
}

/// A rate in hundredths of a percent as the form shows it: 215 as 2.15.
String rateText(int? rate) {
  if (rate == null) return '';
  final whole = rate ~/ 100;
  final cents = rate % 100;
  if (cents == 0) return '$whole';
  return cents % 10 == 0
      ? '$whole.${cents ~/ 10}'
      : '$whole.${'$cents'.padLeft(2, '0')}';
}
