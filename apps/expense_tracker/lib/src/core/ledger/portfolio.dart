import 'dart:math';

import 'package:core/foundation_values.dart' show Currency;
import 'package:domain/investments.dart';

import 'models/models.dart';

/// Holdings replayed from starting positions and investment entries:
/// each stock's lots and what they cost, and how many shares were held
/// after each trade. The same inputs always give the same portfolio.
final class Portfolio {
  Portfolio._(
    this.holdings,
    this.every,
    this._lots,
    this._steps,
    this._counted,
    this._rescales,
    this._reshapes,
    this.leftOut,
    this.faulty,
  );

  /// Replays the trades of [entries] over the [start] positions, in date
  /// order and in the order written within a day. An oversold trade
  /// throws an [OversoldTrade].
  ///
  /// With [lenient], a trade that would oversell is left out instead, so a
  /// book kept before a rule was added still opens; and so is a trade the
  /// replay cannot work with at all, whatever it throws ([faulty]): a book
  /// just read never fails to open over one trade.
  factory Portfolio.replay(
    List<Holding> start,
    List<Entry> entries, {
    bool lenient = false,
  }) {
    final opening = Lot.opening;
    final byCode = {for (final h in start) h.code: h};
    final lots = <String, List<Lot>>{
      for (final h in start)
        h.code: [if (h.shares > 0) Lot(opening, h.shares, h.cost)],
    };
    final steps = <String, List<(DateTime, int)>>{
      for (final h in start) h.code: [(opening, h.shares)],
    };
    final counted = <String, List<(DateTime, int)>>{
      for (final h in start) h.code: [(opening, h.shares)],
    };
    final rescales = <String, List<_Rescale>>{};
    final reshapes = <String, List<_Rescale>>{};
    final leftOut = <String>[];
    final faulty = <String, Object>{};
    for (final e in _inOrder(entries)) {
      final code = e.holding!;
      final held = byCode[code] ?? _firstBought(code, e);
      // Its ratio unknown (none) until it is worked in below.
      final reshaped = e.type == EntryType.dividend && e.shares != 0
          ? ((reshapes[code] ??= [])..add((e.date, 0, 0)))
          : null;
      final Holding? traded;
      try {
        traded = _traded(e, held, lots);
      } on StateError {
        if (!lenient) throw OversoldTrade(e);
        leftOut.add(e.id);
        continue;
      } on Object catch (error) {
        // A trade no rule lets be written (a shape check missed it): read
        // leniently it is left out and named, never thrown.
        if (!lenient) rethrow;
        faulty[e.id] = error;
        continue;
      }
      if (traded != null) byCode[code] = traded;
      final after = traded?.shares ?? held.shares;
      reshaped?.last = (e.date, held.shares, after);
      (counted[code] ??= []).add((e.date, after));
      if (_step(steps[code] ??= [], e, held.shares, after)) {
        (rescales[code] ??= []).add((e.date, held.shares, after));
      }
    }
    final holdings = [
      for (final h in byCode.values)
        if (h.shares > 0 || h.realized != 0) h,
    ]..sort((a, b) => b.value.compareTo(a.value));
    return Portfolio._(
      List.unmodifiable(holdings),
      List.unmodifiable(byCode.values),
      lots,
      steps,
      counted,
      rescales,
      reshapes,
      List.unmodifiable(leftOut),
      Map.unmodifiable(faulty),
    );
  }

  /// The investment entries of [entries] that name a stock, in date order
  /// and in the order written within a day: a sort that kept no order could
  /// put a day's sale before its purchase.
  static List<Entry> _inOrder(List<Entry> entries) {
    final trades = [
      for (final (i, e) in entries.indexed)
        if (e.isInvestment && e.holding != null) (i, e),
    ];
    trades.sort((a, b) {
      final byDate = a.$2.date.compareTo(b.$2.date);
      return byDate != 0 ? byDate : a.$1.compareTo(b.$1);
    });
    return [for (final (_, e) in trades) e];
  }

  /// The stock [code] before its first trade [e]: it takes its first price
  /// per share as the reference until a close is known.
  static Holding _firstBought(String code, Entry e) => Holding(
    code,
    code,
    shares: 0,
    price: e.shares == 0 ? 0 : e.amount / e.shares,
    cost: 0,
    change: 0,
  );

  /// [held] after the trade [e], with its lots in [lots] changed to match;
  /// null for an entry that changes no holding. Throws a [StateError] for
  /// a trade that takes more shares than are held.
  static Holding? _traded(Entry e, Holding held, Map<String, List<Lot>> lots) =>
      switch (e.type) {
        EntryType.buy => _bought(e, held, lots),
        EntryType.sell => _sold(e, held, lots),
        EntryType.dividend when e.isReduction => _reduced(e, held, lots),
        EntryType.dividend when e.shares > 0 && held.shares > 0 => _grown(
          e,
          held,
          lots,
        ),
        EntryType.dividend => _paid(e, held, lots),
        _ => null,
      };

  /// [held] after the purchase [e], which adds a lot of its own.
  static Holding _bought(Entry e, Holding held, Map<String, List<Lot>> lots) {
    final code = e.holding!;
    // What the purchase paid, fee and all, is what its lot cost.
    final cost = -e.settlement;
    lots[code] = [...?lots[code], Lot(e.date, e.shares, cost)];
    return held.copyWith(
      shares: held.shares + e.shares,
      cost: held.cost + cost,
    );
  }

  /// [held] after the sale [e], which takes from its lots.
  static Holding _sold(Entry e, Holding held, Map<String, List<Lot>> lots) {
    final code = e.holding!;
    final (part, rest) = _take(
      lots[code] ?? const [],
      e.shares,
      average: e.average,
    );
    lots[code] = rest;
    return held.copyWith(
      shares: held.shares - e.shares,
      cost: held.cost - part,
      realized: held.realized + e.settlement - part,
    );
  }

  /// [held] after the capital reduction [e], which returns capital and
  /// takes away shares that must be there.
  static Holding _reduced(Entry e, Holding held, Map<String, List<Lot>> lots) {
    final code = e.holding!;
    if (-e.shares > held.shares) {
      throw StateError('A reduction takes more shares than are held.');
    }
    final left = held.shares + e.shares;
    final int lowered;
    var dropped = 0;
    if (left == 0) {
      lots[code] = const [];
      lowered = min(e.amount, held.cost);
    } else {
      final (after, change) = _reratio(
        lots[code] ?? const [],
        left,
        held.shares,
        capitalReturned: e.amount,
      );
      lots[code] = after;
      lowered = change.basisLowered.toInt();
      dropped = change.droppedCost.toInt();
    }
    final worth = max(0.0, held.price * held.shares - e.amount);
    return held.copyWith(
      shares: left,
      cost: held.cost - lowered - dropped,
      price: left == 0 ? held.price : worth / left,
      realized: held.realized + e.amount - lowered - dropped,
    );
  }

  /// [held] after the split or stock dividend [e]: every lot grows,
  /// keeping its cost and its date.
  static Holding _grown(Entry e, Holding held, Map<String, List<Lot>> lots) {
    final code = e.holding!;
    final total = held.shares + e.shares;
    final (after, change) = _reratio(
      lots[code] ?? const [],
      total,
      held.shares,
      wholeShares: !e.split,
    );
    lots[code] = after;
    final dropped = change.droppedCost.toInt();
    return held.copyWith(
      shares: total,
      cost: held.cost - dropped,
      price: e.split ? held.price * held.shares / total : held.price,
      realized: held.realized - dropped,
      dividends: held.dividends + e.dividendNet,
    );
  }

  /// [held] after the dividend [e]. Shares given with nothing held start a
  /// lot of their own.
  static Holding _paid(Entry e, Holding held, Map<String, List<Lot>> lots) {
    final code = e.holding!;
    if (e.shares > 0) {
      lots[code] = [...?lots[code], Lot(e.date, e.shares, 0)];
    }
    return held.copyWith(
      shares: held.shares + e.shares,
      dividends: held.dividends + e.dividendNet,
    );
  }

  /// Adds the [after] shares held after [e] to [kept], [before] being those
  /// held before it. A split or reduction scales the earlier counts to the
  /// new shares; whether it did is returned.
  static bool _step(
    List<(DateTime, int)> kept,
    Entry e,
    int before,
    int after,
  ) {
    final rescaled =
        e.type == EntryType.dividend &&
        before > 0 &&
        (e.split || e.isReduction);
    if (rescaled) {
      for (final (i, (d, n)) in kept.indexed) {
        kept[i] = (d, (n * after / before).round());
      }
    }
    kept.add((e.date, after));
    return rescaled;
  }

  /// Held stocks, and sold ones with a realised result, largest first.
  final List<Holding> holdings;

  /// Every stock held from the start or traded, as the trades leave it,
  /// those [holdings] does not list included (sold out with nothing
  /// gained, dividends and cost left aside).
  final List<Holding> every;

  final Map<String, List<Lot>> _lots;

  /// Each stock's shares after each trade, in date order; counts before a
  /// split or reduction are scaled to today's shares.
  final Map<String, List<(DateTime, int)>> _steps;

  /// Each stock's shares after each trade, in date order, as counted on
  /// its day.
  final Map<String, List<(DateTime, int)>> _counted;

  /// Each stock's splits and reductions, in date order: the day, and the
  /// shares held before and after.
  final Map<String, List<_Rescale>> _rescales;

  /// Each stock's splits, stock dividends and reductions, in date order:
  /// the day, and the shares held before and after (none, 0 and 0, for
  /// one that was not worked in).
  final Map<String, List<_Rescale>> _reshapes;

  /// How many times the shares of [code] were multiplied by the splits,
  /// stock dividends and capital reductions the book holds after [day]
  /// (all, with no day): a close kept on [day] divided by it is what a
  /// close fetched now is expected near (D101, review 18). Null when the
  /// book holds none; one held before which no share was held, or after
  /// which none was left, counts as once, so the reshapes after it still
  /// count (review 25).
  ///
  /// The ratio is the holder's whole shares before and after, not the
  /// company's: a small lot rounds it (5 shares cut 10:1 leave 1, read as
  /// 0.2), and a reshape dated after the market already adjusted counts
  /// again. The close it gives is only the centre of the band a fetched
  /// close is checked against ([takesFetched]), never a price.
  double? reshapedBy(String code, DateTime? day) {
    double? by;
    for (final (date, before, after) in _reshapes[code] ?? const <_Rescale>[]) {
      if (day != null && !date.isAfter(day)) continue;
      by = (by ?? 1) * (before > 0 && after > 0 ? after / before : 1);
    }
    return by;
  }

  /// The trades left out, by id: those an older version let take more
  /// shares than were held, read leniently.
  final List<String> leftOut;

  /// The trades left out, read leniently, because working them in threw
  /// something other than a short sale, by id, with what it threw: a
  /// trade of a shape no rule lets be written. A book just read sets each
  /// aside (holding_repository.dart's `readHoldings`).
  final Map<String, Object> faulty;

  /// The lots of [code] still held, oldest first.
  List<Lot> lotsOf(String code) => List.unmodifiable(_lots[code] ?? const []);

  /// What selling [shares] of [code] now would cost: the oldest lots
  /// first, or the average price.
  int saleCost(String code, int shares, {bool average = false}) =>
      _take(_lots[code] ?? const [], shares, average: average).$1;

  /// The shares of [code] held at the end of [day], in today's shares.
  int sharesOn(String code, DateTime day) {
    var held = 0;
    for (final (date, shares) in _steps[code] ?? const <(DateTime, int)>[]) {
      if (date.isAfter(day)) break;
      held = shares;
    }
    return held;
  }

  /// The shares of [code] held at the end of [day], as counted that day:
  /// no split or reduction since scales them.
  int sharesCountedOn(String code, DateTime day) {
    var held = 0;
    for (final (date, shares) in _counted[code] ?? const <(DateTime, int)>[]) {
      if (date.isAfter(day)) break;
      held = shares;
    }
    return held;
  }

  /// [shares] of [code] held at the end of [day], as counted then, in the
  /// shares a close of the earlier day [of] is a price of (D58): each
  /// split or reduction after [of] up to [day] undone, as such a close is
  /// a price per share of then; one that left no shares is passed over.
  /// A close [fetchedOn] a later day is a price of the shares after each
  /// split or reduction before that day (D123): one of those is not
  /// undone, and one after [day] is worked in.
  int inSharesOf(
    String code,
    DateTime day,
    int shares,
    DateTime of, {
    DateTime? fetchedOn,
  }) {
    bool priced(DateTime date) =>
        !date.isAfter(of) || (fetchedOn != null && date.isBefore(fetchedOn));
    final rescales = _rescales[code] ?? const <_Rescale>[];
    var n = shares;
    for (final (date, before, after) in rescales.reversed) {
      // One that left none (a reduction to nothing) has no shares of
      // before to count back to: the shares counted since are new.
      if (!priced(date) && !date.isAfter(day) && after > 0) {
        n = (n * before / after).round();
      }
    }
    for (final (date, before, after) in rescales) {
      // Nor is one worked forward through: none of before is left.
      if (priced(date) && date.isAfter(day) && before > 0 && after > 0) {
        n = (n * after / before).round();
      }
    }
    return n;
  }

  /// [shares] of [code] held at the end of [day], as they were counted
  /// then, in today's shares: scaled by each split or reduction after
  /// [day] as [sharesOn] scales its earlier counts.
  int inTodaysShares(String code, DateTime day, int shares) {
    var n = shares;
    for (final (date, before, after) in _rescales[code] ?? const <_Rescale>[]) {
      if (date.isAfter(day)) n = (n * after / before).round();
    }
    return n;
  }

  /// The cost of selling [shares] out of [lots], and the lots left: the
  /// ledger's own rule, oldest lots first or at the average cost.
  static (int, List<Lot>) _take(
    List<Lot> lots,
    int shares, {
    required bool average,
  }) {
    final held = lots.fold(BigInt.zero, (sum, l) => sum + l.units);
    final selling = BigInt.from(shares) * unitsPerShare;
    if (selling > held) {
      throw StateError('A sale takes more shares than are held.');
    }
    final sale = sellFromLots(
      _positions(lots),
      selling,
      average ? InvestmentCostMethod.averageCost : InvestmentCostMethod.fifo,
    );
    return (
      sale.cost.toInt(),
      [
        for (final (i, l) in lots.indexed)
          if (sale.remaining[i].units > BigInt.zero)
            Lot.units(
              l.date,
              sale.remaining[i].units,
              sale.remaining[i].cost.toInt(),
            ),
      ],
    );
  }

  /// [lots] after [newShares] for [oldShares], by the ledger's own rule.
  /// Lots that cannot be re-ratioed exactly are pooled into one first,
  /// which always can.
  static (List<Lot>, LotReratio) _reratio(
    List<Lot> lots,
    int newShares,
    int oldShares, {
    bool wholeShares = true,
    int capitalReturned = 0,
  }) {
    LotReratio? change(List<Lot> from) => reratioLots(
      _positions(from),
      newShares: newShares,
      oldShares: oldShares,
      currency: _twd,
      wholeSharesOnly: wholeShares,
      capitalReturned: BigInt.from(capitalReturned),
    );
    var from = lots;
    var result = change(from);
    if (result == null) {
      from = [
        Lot.units(
          lots.last.date,
          lots.fold(BigInt.zero, (sum, l) => sum + l.units),
          lots.fold(0, (sum, l) => sum + l.cost),
        ),
      ];
      result = change(from)!;
    }
    return (
      [
        for (final (i, l) in from.indexed)
          if (result.lots[i].units > BigInt.zero)
            Lot.units(
              l.date,
              result.lots[i].units,
              result.lots[i].cost.toInt(),
            ),
      ],
      result,
    );
  }

  static List<LotPosition> _positions(List<Lot> lots) => [
    for (final l in lots) LotPosition(l.units, BigInt.from(l.cost)),
  ];
}

final _twd = Currency.of(homeCode);

/// A trade that takes more shares than are held by then: [entry], the
/// first one in date order.
final class OversoldTrade extends StateError {
  OversoldTrade(this.entry) : super('A trade takes more shares than are held.');

  /// The sale or reduction that is short.
  final Entry entry;
}

/// A split or reduction: its day, and the shares held before and after.
typedef _Rescale = (DateTime, int, int);
