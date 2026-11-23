import 'package:core/foundation_values.dart';

import '../model/trade_values.dart';

/// What [kind] moves on its account, in the account's smallest unit: the
/// one rule for a trade's money, which the balances, the lists and the
/// forms all ask.
///
/// A buy pays the [gross] and the broker's [fee]; a sale receives the
/// gross less the fee and the securities transaction [tax]; a cash
/// dividend the gross less the NHI premium withheld ([tax]); a capital
/// reduction returns the gross. Money paid out is negative.
int settlementAmount(
  TradeKind kind, {
  required int gross,
  int fee = 0,
  int tax = 0,
}) => switch (kind) {
  TradeKind.buy => -(gross + fee),
  TradeKind.sell => gross - fee - tax,
  TradeKind.dividend => gross - tax,
  TradeKind.capitalReturn => gross,
};

/// Taiwan stock trades settle two exchange days after the trade (T+2), on
/// [calendar]'s open days; the holidays are the calendar's to know.
BusinessDate taiwanSettlementDate(
  BusinessDate tradedOn,
  BankingCalendar calendar,
) => calendar.addOpenDays(tradedOn, 2);
