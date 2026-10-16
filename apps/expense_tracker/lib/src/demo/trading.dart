import 'dart:math';

/// The broker's fee on a trade of [amount]: 0.1425% at [discount], at
/// least NT$20 for whole lots and NT$1 for odd lots.
int brokerFee(int amount, int shares, {double discount = 0.6}) {
  if (amount <= 0) return 0;
  final fee = (amount * 0.001425 * discount).floor();
  return max(fee, shares % 1000 == 0 ? 20 : 1);
}

/// The securities transaction tax on a sale: 0.1% for ETFs, whose codes
/// start with 00, and 0.3% for shares.
int saleTax(String code, int amount) =>
    (amount * (code.startsWith('00') ? 0.001 : 0.003)).floor();

/// When a trade on [day] settles: two weekdays later.
DateTime settlementDay(DateTime day) {
  var settled = day;
  var left = 2;
  while (left > 0) {
    settled = settled.add(const Duration(days: 1));
    if (settled.weekday <= DateTime.friday) left--;
  }
  return settled;
}
