import 'package:core/foundation_values.dart';
import 'package:ledger_trade_costs/calc/charges.dart';
import 'package:ledger_trade_costs/calc/settlement.dart';
import 'package:ledger_trade_costs/model/trade_values.dart';
import 'package:ledger_trade_costs/rules/instruments.dart';

/// The broker's discount on the fee before it is set, in basis points of
/// the full fee: 6折. The one setting that changes it is the preference
/// 券商手續費折扣; this is its default.
const defaultBrokerDiscount = 6000;

/// [code] as the exchanges write it: no spaces, upper case, without a
/// `.TW` or `.TWO` ending.
String tidyCode(String code) => tidyStockCode(code);

/// Whether the exchanges quote [code], so its closing price can be fetched.
bool quotable(String code) => isTaiwanSymbol(code);

/// Suggested charges for the composer, from the ledger's own Taiwan rules
/// (`TaiwanTradeCharges`, `TaiwanRates`), so what it suggests is what the
/// ledger would work out. The person can still type what was charged.
final _twd = Currency.of('TWD');

Money _ntd(int amount) => Money(_twd, BigInt.from(amount));

BusinessDate _day(DateTime date) =>
    BusinessDate(date.year, date.month, date.day);

/// The broker's fee on a trade of [amount] for [shares]: 0.1425% at the
/// [discount] (basis points of the full fee, 6折 unless set), at least
/// NT$20 for a board lot and NT$1 for an odd lot.
int brokerFee(int amount, int shares, {int discount = defaultBrokerDiscount}) {
  if (amount <= 0 || shares <= 0) return 0;
  final quantity = ShareQuantity.parse('$shares');
  final charges = TaiwanTradeCharges(discountBasisPoints: discount);
  return charges.fee(_ntd(amount), quantity).minorUnits.toInt();
}

/// The securities transaction tax on selling [shares] of [code] for
/// [amount] on [tradedOn], at that day's rate; codes starting with 00 are
/// ETFs, and those ending in B bond ETFs.
int saleTax(String code, int amount, int shares, DateTime tradedOn) {
  if (amount <= 0 || shares <= 0) return 0;
  final kind = instrumentKindOf(code);
  try {
    return TaiwanTradeCharges()
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
    // Before the rates on record: nothing to suggest.
    return 0;
  }
}

/// When a trade on [day] settles: two open days of [calendar] later
/// (T+2). By default only weekends are skipped, so a trade before a
/// holiday settles a day early; Taiwan's holidays are
/// `taiwanHolidays.banking`, left out until the owner decides.
DateTime settlementDay(DateTime day, {BankingCalendar? calendar}) {
  final settles = taiwanSettlementDate(
    _day(day),
    calendar ?? BankingCalendar(),
  );
  return DateTime.utc(settles.year, settles.month, settles.day);
}
