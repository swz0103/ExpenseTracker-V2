part of 'compose_form.dart';

// A buy or sale of shares: what the shares sold cost, and when it settles;
// and how a dividend changes the shares held.

/// How a dividend changes the shares held: not at all, by shares paid out
/// (配股), by a split (分割), or by a capital reduction (減資).
enum ShareChange { none, stockDividend, split, capitalReduction }

extension TradeFields on ComposeForm {
  /// What the shares being sold cost, by the method chosen ([average] or
  /// first in, first out), from the lots held on the sale's day: the
  /// book's trades up to then, the sale being changed left out. Null for
  /// a buy, before a holding is chosen, and for more shares than were
  /// held then, which no cost answers.
  int? get saleCost {
    final code = holding;
    if (trade != EntryType.sell || code == null) return null;
    return ledger.holdings.saleCostWith(
      tradesBefore,
      code,
      shares,
      average: average,
    );
  }

  /// The book's entries before the one being written: those of earlier
  /// days and, on its day, those written before it; the entry being
  /// changed is left out, and so is all that follows it on its day.
  List<Entry> get tradesBefore {
    final changed = editing;
    final before = <Entry>[];
    var past = false;
    for (final e in ledger.entries.all) {
      if (changed != null && e.id == changed.id) {
        past = true;
        continue;
      }
      if (e.date.isAfter(date)) continue;
      // On the day itself, a new entry comes after all; one changed keeps
      // its place, unless it moved to another day.
      if (past && changed!.date == date && e.date == date) continue;
      before.add(e);
    }
    return before;
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
