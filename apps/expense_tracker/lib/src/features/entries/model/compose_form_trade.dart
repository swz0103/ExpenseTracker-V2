part of 'compose_form.dart';

// A buy or sale of shares: what the shares sold cost, and when it settles.

extension TradeFields on ComposeForm {
  /// What the shares being sold cost, by the method chosen ([average] or
  /// first in, first out); null for a buy, before a holding is chosen, and
  /// for more shares than are held, which no cost answers.
  int? get saleCost {
    final code = holding;
    if (trade != EntryType.sell || code == null) return null;
    final held = ledger.holding(code);
    if (held == null || shares > held.shares) return null;
    return ledger.holdings.saleCost(code, shares, average: average);
  }

  /// The day the trade settles: two weekdays after it (T+2).
  DateTime get settles => settlementDay(date);
}
