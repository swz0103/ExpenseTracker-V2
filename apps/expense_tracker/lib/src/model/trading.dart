import 'package:core/foundation_values.dart';
import 'package:domain/investments.dart';

/// Suggested charges for the composer, from the ledger's own Taiwan rules
/// (`TaiwanTradeCharges`, `TaiwanRates`), so what it suggests is what the
/// ledger would work out. The person can still type what was charged.
final _charges = TaiwanTradeCharges(discountBasisPoints: 6000);
final _twd = Currency.of('TWD');

Money _ntd(int amount) => Money(_twd, BigInt.from(amount));

BusinessDate _day(DateTime date) =>
    BusinessDate(date.year, date.month, date.day);

/// The broker's fee on a trade of [amount] for [shares]: 0.1425% at a 6折
/// discount, at least NT$20 for a board lot and NT$1 for an odd lot.
int brokerFee(int amount, int shares) {
  if (amount <= 0 || shares <= 0) return 0;
  final quantity = ShareQuantity.parse('$shares');
  return _charges.fee(_ntd(amount), quantity).minorUnits.toInt();
}

/// The securities transaction tax on selling [shares] of [code] for
/// [amount] on [tradedOn], at that day's rate; codes starting with 00 are
/// ETFs, and those ending in B bond ETFs.
int saleTax(String code, int amount, int shares, DateTime tradedOn) {
  if (amount <= 0 || shares <= 0) return 0;
  final kind = !code.startsWith('00')
      ? InstrumentKind.stock
      : code.toUpperCase().endsWith('B')
      ? InstrumentKind.bondEtf
      : InstrumentKind.etf;
  try {
    return _charges
        .sellTax(
          _ntd(amount),
          ShareQuantity.parse('$shares'),
          kind: kind,
          tradedOn: _day(tradedOn),
        )
        .minorUnits
        .toInt();
  } on InvestmentException {
    // Before the rates on record: nothing to suggest.
    return 0;
  }
}

/// The NHI supplementary premium (二代健保) withheld from a cash dividend
/// of [gross] paid on [paidOn]: 2.11% once one payment reaches NT$20,000.
int dividendPremium(int gross, DateTime paidOn) {
  if (gross <= 0) return 0;
  try {
    final premium = supplementaryPremium(_ntd(gross), paidOn: _day(paidOn));
    return premium.minorUnits.toInt();
  } on InvestmentException {
    return 0;
  }
}

/// When a trade on [day] settles: two weekdays later (T+2). Holidays are
/// not known here, so a trade before one settles a day early.
DateTime settlementDay(DateTime day) {
  final settles = taiwanSettlementDate(_day(day), BankingCalendar());
  return DateTime.utc(settles.year, settles.month, settles.day);
}
