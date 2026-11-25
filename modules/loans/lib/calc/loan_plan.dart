/// How a loan is paid back: the same each month (本息平均攤還), the same
/// share of the loan each month (本金平均攤還), or only the interest.
enum LoanRepay { even, principal, interest }

/// How a fraction of the smallest unit of money is settled: half and
/// above goes up ([halfUp], 四捨五入), or everything is dropped ([down],
/// 無條件捨去).
enum LoanRounding { halfUp, down }

/// The one rounding of a loan's interest and of its level payment: half
/// up to the whole NT$, as Taiwanese banks do (四捨五入至元). Each month's
/// interest is rounded on its own, so a schedule here matches the bank's
/// month by month and not only in total.
const loanInterestRounding = LoanRounding.halfUp;

/// One month of a loan: what is paid, how much of it is interest and how
/// much pays the loan down, and what is still owed afterwards.
typedef LoanPeriod = ({int payment, int interest, int principal, int balance});

/// What a loan costs as set: the first and last month's payment and the
/// interest over its whole term, in whole NT$.
typedef LoanPlan = ({int first, int last, int interest});

/// [numerator] / [denominator] (both positive or zero over positive) as
/// a whole number, the fraction settled by [rounding].
BigInt roundedQuotient(
  BigInt numerator,
  BigInt denominator,
  LoanRounding rounding,
) => switch (rounding) {
  LoanRounding.down => numerator ~/ denominator,
  LoanRounding.halfUp =>
    (numerator * BigInt.two + denominator) ~/ (denominator * BigInt.two),
};

/// A year's rate in hundredths of a percent, over twelve months, as the
/// divisor of `amount x rate`: 100 x 100 x 12.
final _monthly = BigInt.from(120000);

/// Every month of [amount] borrowed at [rate] (hundredths of a percent a
/// year) over [months], paid back by [repay]: the one schedule every loan
/// figure comes from. Null while something is missing, or for a rate
/// below nothing, which the write rules refuse (D116); a missing rate is
/// no interest.
///
/// Each month's interest is what is still owed x the monthly rate,
/// rounded on its own by [loanInterestRounding].
///
/// * [LoanRepay.even]: the payment is the annuity payment
///   `P r / (1 - (1 + r)^-n)`, rounded once; a month pays down the payment
///   less its interest, and the last month pays off exactly what is left,
///   so its payment differs by what rounding gathered.
/// * [LoanRepay.principal]: each month pays down `amount ~/ months`; what
///   the division leaves over goes with the last month.
/// * [LoanRepay.interest]: each month pays interest only and the last one
///   the loan as well. The rate never changes what is owed, so the months
///   are the steps of the exact interest so far, rounded: they add up to
///   the exact interest of the term.
///
/// All in whole numbers, so no figure depends on floating point.
List<LoanPeriod>? loanSchedule({
  required int? amount,
  required int? rate,
  required int? months,
  required LoanRepay repay,
}) {
  if (amount == null || amount <= 0) return null;
  if (months == null || months <= 0) return null;
  if (rate != null && rate < 0) return null;
  final yearly = BigInt.from(rate ?? 0);
  int interestOn(int owed, [int forMonths = 1]) => roundedQuotient(
    BigInt.from(owed) * yearly * BigInt.from(forMonths),
    _monthly,
    loanInterestRounding,
  ).toInt();

  final level = repay == LoanRepay.even
      ? _levelPayment(amount, yearly, months)
      : 0;
  final share = amount ~/ months;
  final periods = <LoanPeriod>[];
  var owed = amount;
  for (var k = 1; k <= months; k++) {
    final last = k == months;
    final interest = switch (repay) {
      LoanRepay.interest => interestOn(amount, k) - interestOn(amount, k - 1),
      LoanRepay.even || LoanRepay.principal => interestOn(owed),
    };
    final wanted = switch (repay) {
      LoanRepay.interest => 0,
      LoanRepay.principal => share,
      LoanRepay.even => level - interest,
    };
    // Never below nothing nor above what is owed: a loan of a few NT$
    // over many months rounds to a payment that ends it early.
    final principal = last ? owed : wanted.clamp(0, owed);
    owed -= principal;
    periods.add((
      payment: interest + principal,
      interest: interest,
      principal: principal,
      balance: owed,
    ));
  }
  return periods;
}

/// The plan for [amount] borrowed at [rate] (hundredths of a percent a
/// year) over [months], paid back by [repay], read off [loanSchedule];
/// null while something is missing.
LoanPlan? loanPlan({
  required int? amount,
  required int? rate,
  required int? months,
  required LoanRepay repay,
}) {
  final schedule = loanSchedule(
    amount: amount,
    rate: rate,
    months: months,
    repay: repay,
  );
  if (schedule == null) return null;
  var interest = 0;
  for (final period in schedule) {
    interest += period.interest;
  }
  return (
    first: schedule.first.payment,
    last: schedule.last.payment,
    interest: interest,
  );
}

/// The level payment of an equal-payment loan, rounded once:
/// `P r / (1 - (1 + r)^-n)` with `r = yearly / 120000`, which in whole
/// numbers is `P yearly q^n / (120000 (q^n - 120000^n))` for
/// `q = 120000 + yearly`. At no interest it is the even share.
int _levelPayment(int amount, BigInt yearly, int months) {
  final principal = BigInt.from(amount);
  if (yearly == BigInt.zero) {
    return roundedQuotient(
      principal,
      BigInt.from(months),
      loanInterestRounding,
    ).toInt();
  }
  final grown = (_monthly + yearly).pow(months);
  return roundedQuotient(
    principal * yearly * grown,
    _monthly * (grown - _monthly.pow(months)),
    loanInterestRounding,
  ).toInt();
}
