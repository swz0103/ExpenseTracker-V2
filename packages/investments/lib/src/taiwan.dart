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

  /// The securities transaction tax on a sell: 0.3% for stocks, 0.15% for
  /// a day trade, 0.1% for ETFs. Buys pay none.
  Money sellTax(
    Money gross,
    ShareQuantity quantity, {
    required InstrumentKind kind,
    bool dayTrade = false,
  }) {
    _check(gross, quantity);
    final perTenThousand = switch (kind) {
      InstrumentKind.etf => 10,
      InstrumentKind.stock => dayTrade ? 15 : 30,
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

/// Taiwan stock trades settle two exchange days after the trade (T+2,
/// feature audit G-07).
BusinessDate taiwanSettlementDate(
  BusinessDate tradedOn,
  BankingCalendar calendar,
) => calendar.addOpenDays(tradedOn, 2);

final _twd = Currency.of('TWD');
