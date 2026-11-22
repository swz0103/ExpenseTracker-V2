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
      // The interest of the first k months, rounded once; each month pays
      // the step from k - 1 to k, so the months add up to the whole and
      // the last one takes what rounding left over.
      int upTo(int k) => _interestOf(amount, rate ?? 0, k);
      final interest = upTo(months);
      return (
        first: upTo(1),
        last: amount + interest - upTo(months - 1),
        interest: interest,
      );
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

/// [amount] x [rate] (hundredths of a percent a year) x [months] / 12,
/// rounded half up to a whole NT$; in big integers, so a large loan over
/// many months cannot overflow.
int _interestOf(int amount, int rate, int months) {
  final numerator =
      BigInt.from(amount) * BigInt.from(rate) * BigInt.from(months);
  final denominator = BigInt.from(120000);
  return ((numerator * BigInt.two + denominator) ~/ (denominator * BigInt.two))
      .toInt();
}
