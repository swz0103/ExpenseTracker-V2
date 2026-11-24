import 'package:core/money/price.dart' show timesPrice;
import 'package:kernel/kernel.dart';
import 'package:ledger_postings/model/vocabulary.dart' show Owners;

import '../repositories/holding_repository.dart';
import '../repositories/market_data_repository.dart';

/// What the journal's net worth values a unit at, as the app values it
/// (`BalanceService.netWorthAt`): a stock the holdings list at its price
/// per whole share held; a foreign currency at the market's buying rate
/// when held and selling rate when owed (D59); any
/// other unit (a stock sold and no longer listed, a currency with no
/// rate yet) at nothing, as the app counts it.
Contributions valuedAsTheApp({
  required HoldingReader holdings,
  required MarketDataReader market,
}) => Contributions()
  ..on(valuers).add(
    Owners.investments,
    (unit, amount, asOf) => switch (holdings.byCode(unit)) {
      final h? => timesPrice(wholeUnits(amount), h.price),
      null => market.valueAtHome(amount.toInt(), unit) ?? 0,
    },
  );
