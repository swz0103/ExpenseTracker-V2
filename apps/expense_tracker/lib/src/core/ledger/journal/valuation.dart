import 'package:core/money/price.dart' show timesPrice;
import 'package:kernel/kernel.dart';
import 'package:ledger_postings/model/vocabulary.dart' show Owners;

import '../repositories/holding_repository.dart';
import '../repositories/market_data_repository.dart';
import '../services/dated_worth.dart';

/// What the journal's net worth values a unit at, as the app values it
/// (`BalanceService.netWorthAt`, D105): a stock ever held at the close
/// of the day, else the nearest earlier day's, in that day's shares
/// (`datedWorth`, D58), else at today's price per whole share held that
/// day, in today's shares; a foreign currency at the day's buying rate
/// when held and selling rate when owed (D58, D59); any other unit (a
/// currency with no rate yet) at nothing, as the app counts it.
Contributions valuedAsTheApp({
  required HoldingReader holdings,
  required MarketDataReader market,
}) =>
    Contributions()
      ..on(valuers).add(Owners.investments, (unit, amount, asOf) {
        final day = asOf.date.asUtcMidnight;
        return switch (holdings.everByCode(unit)) {
          final h? =>
            datedWorth(
                  holdings: holdings,
                  market: market,
                  code: unit,
                  day: day,
                  counted: wholeUnits(amount),
                ) ??
                timesPrice(
                  holdings.inTodaysShares(unit, day, wholeUnits(amount)),
                  h.price,
                ),
          null => market.valueAtHomeOn(amount.toInt(), unit, day) ?? 0,
        };
      });
