import 'package:core/foundation_values.dart';

import '../model/trade_values.dart';
import 'broker_discount.dart';
import '../rules/taiwan_rates.dart';

/// Suggested Taiwan brokerage fee and securities transaction tax for a
/// trade; the user can still type what the broker actually charged.
/// Amounts are in whole New Taiwan dollars and rounded down, as brokers do.
final class TaiwanTradeCharges {
  /// [discountBasisPoints] is the broker's discount: 10000 for none, 2800
  /// for 2.8折, within [BrokerDiscountRange]. Board lots pay at least [minimumFee]; odd lots (fewer
  /// than 1000 shares) at least [oddLotMinimumFee].
  TaiwanTradeCharges({
    this.discountBasisPoints = 10000,
    int minimumFee = 20,
    int oddLotMinimumFee = 1,
  }) : minimumFee = Money(_twd, BigInt.from(minimumFee)),
       oddLotMinimumFee = Money(_twd, BigInt.from(oddLotMinimumFee)) {
    if (!BrokerDiscountRange.holds(discountBasisPoints) ||
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
  /// for ETFs, none for bond ETFs while exempt. Buys pay none.
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
      InstrumentKind.bondEtf => rates.bondEtfTax,
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
/// on at most NT$10 million, rounded half up.
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

final _twd = Currency.of('TWD');
