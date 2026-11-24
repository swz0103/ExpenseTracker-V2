part of 'compose_form.dart';

// A buy or sale of shares: what the shares sold cost, and when it settles;
// and how a dividend changes the shares held.

/// How a dividend changes the shares held: not at all, by shares paid out
/// (配股), by a split (分割), or by a capital reduction (減資).
enum ShareChange { none, stockDividend, split, capitalReduction }

extension TradeFields on ComposeForm {
  /// The broker's fee and tax the ledger's Taiwan rules suggest for the
  /// trade being written.
  (int, int) get suggested =>
      _suggestedFor(type, holding ?? '', amount, shares, date, dayTrade);

  /// The broker's discount a trade from or into [account] is charged at:
  /// the account's own, else the phone-wide [brokerDiscount] (D7).
  int get tradeDiscount =>
      ledger.accounts.byId(account)?.brokerDiscount ?? brokerDiscount;

  /// The fee and tax the rules suggest for a [kind] of [shares] of [code]
  /// for [amount] on [day], at the [tradeDiscount]; a [dayTrade] sale at
  /// the day-trade tax rate.
  (int, int) _suggestedFor(
    EntryType kind,
    String code,
    int amount,
    int shares,
    DateTime day,
    bool dayTrade,
  ) {
    final tax = kind == EntryType.sell
        ? saleTax(code, amount, shares, day, dayTrade: dayTrade)
        : 0;
    return (brokerFee(amount, shares, discount: tradeDiscount), tax);
  }

  /// The trade's fee and tax: as typed, else as suggested.
  (int, int) get charges {
    if (type != EntryType.buy && type != EntryType.sell) return (0, 0);
    final (fee, tax) = suggested;
    return (tradeFee ?? fee, tradeTax ?? tax);
  }

  /// What a trade settles at, by the same rule as the saved entry
  /// (`settlementAmount`): paid for a buy with its fee, received for a
  /// sale less fee and tax; as a size, without its sign.
  int get settlement {
    final (fee, tax) = charges;
    final kind = trade == EntryType.sell ? TradeKind.sell : TradeKind.buy;
    return settlementAmount(kind, gross: amount, fee: fee, tax: tax).abs();
  }

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

  /// The day the trade settles: two exchange days after it (T+2),
  /// holidays skipped where the calendar knows the year.
  BusinessDayAnswer<BusinessDate> get settles => settlementDay(date);

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

/// What the ledger says before a trade is kept, such as a cash account
/// left below nothing by buying shares (F24).
extension SaveWarning on ComposeForm {
  /// What the ledger says before keeping the entry, which may still be
  /// kept, such as a cash account left below nothing by buying shares;
  /// null when nothing, or while the entry would be refused. Worked out
  /// once per change of the entry or the book, not on every frame that
  /// shows it.
  String? get warning {
    final made = buildAll();
    final key = '${ledger.revision}|${made.map(_fields).join('|')}';
    if (key == _warnedFor) return _warned;
    _warnedFor = key;
    return _warned = _warningOf(made);
  }

  String? _warningOf(List<Entry> made) {
    RecordIssue? said;
    for (final e in made) {
      final was = ledger.entries.byId(e.id);
      // The shares a sale takes are the save's to check, by replaying the
      // trades; no warning rests on them.
      for (final issue in ledger.entryValidator.issues(
        e,
        replacing: was,
        holdings: false,
      )) {
        if (issue.isError) return null;
        said ??= issue;
      }
    }
    return said == null ? null : validationMessage(said);
  }

  /// Every field of [e] but its id, which a new entry draws afresh each
  /// time it is built.
  static String _fields(Entry e) => (
    e.date,
    e.type,
    e.amount,
    e.account,
    e.category,
    e.to,
    e.holding,
    e.shares,
    e.parts,
    e.fee,
    e.tax,
    e.refundOf,
    e.installments,
    e.average,
    e.dayTrade,
    e.split,
    e.home,
    e.received,
    e.group,
  ).toString();
}
