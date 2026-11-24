import 'package:core/money/price.dart' show timesPrice;
import 'package:kernel/kernel.dart';
import 'package:ledger_postings/model/vocabulary.dart' show Owners;

import '../repositories/holding_repository.dart';
import '../repositories/market_data_repository.dart';

/// What the journal's net worth values a unit at, as the app values it
/// (`BalanceService.netWorthAt`, D105): a stock ever held at today's
/// price per whole share held that day, in today's shares; a foreign
/// currency at the market's buying rate when held and selling rate when
/// owed (D59); any other unit (a currency with no rate yet) at nothing,
/// as the app counts it.
Contributions valuedAsTheApp({
  required HoldingReader holdings,
  required MarketDataReader market,
}) => Contributions()
  ..on(valuers).add(
    Owners.investments,
    (unit, amount, asOf) => switch (holdings.everByCode(unit)) {
      final h? => timesPrice(
        holdings.inTodaysShares(
          unit,
          asOf.date.asUtcMidnight,
          wholeUnits(amount),
        ),
        h.price,
      ),
      null => market.valueAtHome(amount.toInt(), unit) ?? 0,
    },
  );
