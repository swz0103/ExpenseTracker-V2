import 'package:core/money/price.dart' show timesPrice;

import '../repositories/holding_repository.dart';
import '../repositories/market_data_repository.dart';

/// What [counted] shares of [code], as counted at the end of [day], are
/// worth in whole NT$ at a close older than the latest (D58, D105): the
/// close of [day], else of the nearest earlier day kept, in that day's
/// shares. Null when the close found is the latest kept, or none is kept
/// for [day] or before: the holding's price today then values them, in
/// today's shares, as the holdings show them. The one rule of the app's
/// net worth on a day and the journal's.
int? datedWorth({
  required HoldingReader holdings,
  required MarketDataReader market,
  required String code,
  required DateTime day,
  required int counted,
}) {
  final close = market.closeOn(code, day);
  if (close == null || close.found.isTodays) return null;
  final of = close.of;
  if (of == null || of == market.history.closes.latestOf(code)) return null;
  return timesPrice(
    holdings.inSharesOf(code, day, counted, of.asUtcMidnight),
    close.figure,
  );
}
