import 'package:foundation_values/foundation_values.dart';

import 'buy.dart';

/// Suggested Taiwan brokerage fee and securities transaction tax for a
/// trade; the user can still type what the broker actually charged
/// (feature audit G-05). Amounts are in whole New Taiwan dollars and
/// rounded down, as brokers do.
final class TaiwanTradeCharges {
  /// [discountBasisPoints] is the broker's discount: 10000 for none, 2800
  /// for 2.8折. Board lots pay at least [minimumFee]; odd lots (fewer
  /// than 1000 shares) at least [oddLotMinimumFee].
  TaiwanTradeCharges({
    this.discountBasisPoints = 10000,
    int minimumFee = 20,
    int oddLotMinimumFee = 1,
  }) : minimumFee = Money(_twd, BigInt.from(minimumFee)),
       oddLotMinimumFee = Money(_twd, BigInt.from(oddLotMinimumFee)) {
    if (discountBasisPoints < 1 ||
        discountBasisPoints > 10000 ||
        minimumFee < 0 ||
        oddLotMinimumFee < 0) {
      throw const InvestmentException(InvestmentError.invalidInput);
    }
  }

  final int discountBasisPoints;
  final Money minimumFee;
  final Money oddLotMinimumFee;

  /// 0.1425% of [gross] after the discount, at least the minimum.
  Money fee(Money gross, ShareQuantity quantity) {
    _check(gross, quantity);
    if (gross.minorUnits == BigInt.zero) return gross;
    final fee =
        gross.minorUnits *
        BigInt.from(1425 * discountBasisPoints) ~/
        BigInt.from(1000000 * 10000);
    final oddLot = quantity.coefficient < BigInt.from(1000);
    final minimum = oddLot ? oddLotMinimumFee : minimumFee;
    return fee < minimum.minorUnits ? minimum : Money(_twd, fee);
  }

  /// The securities transaction tax on a sell [tradedOn] that day, from
  /// [TaiwanRates.on]: today 0.3% for stocks, 0.15% for a day trade, 0.1%
  /// for ETFs. Buys pay none.
  Money sellTax(
    Money gross,
    ShareQuantity quantity, {
    required InstrumentKind kind,
    required BusinessDate tradedOn,
    bool dayTrade = false,
  }) {
    _check(gross, quantity);
    final rates = TaiwanRates.on(tradedOn);
    final perTenThousand = switch (kind) {
      InstrumentKind.etf => rates.etfTax,
      InstrumentKind.stock => dayTrade ? rates.dayTradeTax : rates.stockTax,
    };
    return Money(
      _twd,
      gross.minorUnits * BigInt.from(perTenThousand) ~/ BigInt.from(10000),
    );
  }

  static void _check(Money gross, ShareQuantity quantity) {
    if (gross.currency != _twd) {
      throw const InvestmentException(InvestmentError.currencyMismatch);
    }
    if (gross.minorUnits.isNegative) {
      throw const InvestmentException(InvestmentError.invalidInput);
    }
    if (!quantity.isWhole) {
      throw const InvestmentException(InvestmentError.fractionalShares);
    }
  }
}

/// Taiwan's NHI supplementary premium on one dividend paid [paidOn], from
/// [TaiwanRates.on]: today 2.11% of the gross when it reaches NT$20,000,
/// on at most NT$10 million, rounded half up (feature audit G-13).
Money supplementaryPremium(Money gross, {required BusinessDate paidOn}) {
  if (gross.currency != _twd) {
    throw const InvestmentException(InvestmentError.currencyMismatch);
  }
  if (gross.minorUnits.isNegative) {
    throw const InvestmentException(InvestmentError.invalidInput);
  }
  final rates = TaiwanRates.on(paidOn);
  if (gross.minorUnits < BigInt.from(rates.premiumThreshold)) {
    return Money(_twd, BigInt.zero);
  }
  final cap = BigInt.from(10000000);
  final base = gross.minorUnits > cap ? cap : gross.minorUnits;
  return Money.quantizeRatio(
    _twd,
    base * BigInt.from(rates.premiumBasisPoints),
    BigInt.from(10000),
  );
}

/// Taiwan's tax and premium rates in force from [from]. Suggestions use
/// the rates of the trade's or payment's own date, so a change in the law
/// never changes an older suggestion (code audit 4.3). Taxes are per ten
/// thousand of the gross; the premium in basis points.
final class TaiwanRates {
  const TaiwanRates._({
    required this.from,
    required this.stockTax,
    required this.dayTradeTax,
    required this.etfTax,
    required this.premiumBasisPoints,
    required this.premiumThreshold,
  });

  final BusinessDate from;
  final int stockTax;
  final int dayTradeTax;
  final int etfTax;
  final int premiumBasisPoints;

  /// In whole New Taiwan dollars.
  final int premiumThreshold;

  /// Oldest first. Day-trade tax is halved from 2017-04-28 through
  /// 2027-12-31 by law; an extension adds a row here.
  static final history = List<TaiwanRates>.unmodifiable([
    TaiwanRates._(
      from: BusinessDate(2016, 1, 1),
      stockTax: 30,
      dayTradeTax: 30,
      etfTax: 10,
      premiumBasisPoints: 191,
      premiumThreshold: 20000,
    ),
    TaiwanRates._(
      from: BusinessDate(2017, 4, 28),
      stockTax: 30,
      dayTradeTax: 15,
      etfTax: 10,
      premiumBasisPoints: 191,
      premiumThreshold: 20000,
    ),
    TaiwanRates._(
      from: BusinessDate(2021, 1, 1),
      stockTax: 30,
      dayTradeTax: 15,
      etfTax: 10,
      premiumBasisPoints: 211,
      premiumThreshold: 20000,
    ),
    TaiwanRates._(
      from: BusinessDate(2028, 1, 1),
      stockTax: 30,
      dayTradeTax: 30,
      etfTax: 10,
      premiumBasisPoints: 211,
      premiumThreshold: 20000,
    ),
  ]);

  /// The rates on [date]. Before 2016 there is no suggestion; the user
  /// types what was charged.
  static TaiwanRates on(BusinessDate date) {
    for (final rates in history.reversed) {
      if (rates.from.compareTo(date) <= 0) return rates;
    }
    throw const InvestmentException(InvestmentError.invalidInput);
  }
}

/// Taiwan stock trades settle two exchange days after the trade (T+2,
/// feature audit G-07).
BusinessDate taiwanSettlementDate(
  BusinessDate tradedOn,
  BankingCalendar calendar,
) => calendar.addOpenDays(tradedOn, 2);

final _twd = Currency.of('TWD');
