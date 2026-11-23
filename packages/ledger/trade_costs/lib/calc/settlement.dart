import 'package:core/foundation_values.dart';

import '../model/trade_values.dart';
import '../rules/taiwan_market_days.dart';

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

/// When a Taiwan stock trade of [tradedOn] settles: two exchange days
/// later (T+2, [taiwanSettlementDays]) on [calendar], which skips
/// weekends and days off; the exchanges' days are `taiwanMarketDays`.
///
/// [Verified] when every day counted is in a year the calendar knows;
/// otherwise [WeekendsOnly]: days off in the unknown year were not
/// skipped, and the caller says so.
BusinessDayAnswer<BusinessDate> taiwanSettlementDate(
  BusinessDate tradedOn,
  HolidayCalendar calendar,
) => calendar.addBusinessDays(tradedOn, taiwanSettlementDays);
