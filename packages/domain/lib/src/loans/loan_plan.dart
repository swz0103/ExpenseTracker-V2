import 'dart:math' as math;

/// How a loan is paid back: the same each month (本息平均攤還), the same
/// share of the loan each month (本金平均攤還), or only the interest.
enum LoanRepay { even, principal, interest }

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

/// A rate as typed, such as 「2.15」, in hundredths of a percent; null
/// when it is not a number from 0 to 100.
///
/// Read from the digits themselves, not through a double, which holds
/// 1.005 as 1.00499...: past two places it rounds half up, as written.
int? rateOf(String typed) {
  final match = RegExp(r'^(\d*)(?:\.(\d*))?$').firstMatch(typed.trim());
  if (match == null || !typed.contains(RegExp(r'\d'))) return null;
  final decimals = match[2] ?? '';
  final whole = int.tryParse(match[1]!) ?? 0;
  final kept = int.parse(decimals.padRight(2, '0').substring(0, 2));
  final next = decimals.length > 2 ? int.parse(decimals[2]) : 0;
  final hundredths = whole * 100 + kept + (next >= 5 ? 1 : 0);
  return hundredths > 10000 ? null : hundredths;
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
