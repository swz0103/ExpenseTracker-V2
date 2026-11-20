part of 'compose_form.dart';

// A buy or sale of shares: what the shares sold cost, and when it settles;
// and how a dividend changes the shares held.

/// How a dividend changes the shares held: not at all, by shares paid out
/// (配股), by a split (分割), or by a capital reduction (減資).
enum ShareChange { none, stockDividend, split, capitalReduction }

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

  /// How the dividend being written changes the shares held.
  ShareChange get shareChangeKind => !shareChange
      ? ShareChange.none
      : reduce
      ? ShareChange.capitalReduction
      : splitShares
      ? ShareChange.split
      : ShareChange.stockDividend;

  /// Changes the shares held by [kind]; none leaves no shares written.
  void setShareChange(ShareChange kind) {
    shareChange = kind != ShareChange.none;
    splitShares = kind == ShareChange.split;
    reduce = kind == ShareChange.capitalReduction;
    if (kind == ShareChange.none) shares = 0;
  }
}
