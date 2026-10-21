import 'dart:math';

import 'package:core/foundation_values.dart' show Currency;
import 'package:domain/investments.dart';

import 'records.dart';

/// Holdings replayed from starting positions and investment entries:
/// each stock's lots and what they cost, and how many shares were held
/// after each trade. The same inputs always give the same portfolio.
final class Portfolio {
  Portfolio._(this.holdings, this._lots, this._steps);

  /// Replays the trades of [entries] over the [start] positions, in date
  /// order and in the order written within a day. An oversold trade
  /// throws a [StateError].
  ///
  /// With [lenient], a trade that would oversell is left out instead, so a
  /// book kept before a rule was added still opens.
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
    // In date order, and in the order written within a day: a sort that
    // kept no order could put a day's sale before its purchase.
    final trades = [
      for (final (i, e) in entries.indexed)
        if (e.isInvestment && e.holding != null) (i, e),
    ];
    trades.sort((a, b) {
      final byDate = a.$2.date.compareTo(b.$2.date);
      return byDate != 0 ? byDate : a.$1.compareTo(b.$1);
    });
    final steps = <String, List<(DateTime, int)>>{
      for (final h in start) h.code: [(opening, h.shares)],
    };
    for (final (_, e) in trades) {
      final code = e.holding!;
      // A stock bought for the first time takes its first price per share
      // as the reference until a close is known.
      final held =
          byCode[code] ??
          Holding(
            code,
            code,
            shares: 0,
            price: e.shares == 0 ? 0 : e.amount / e.shares,
            cost: 0,
            change: 0,
          );
      try {
      switch (e.type) {
        case EntryType.buy:
          final cost = e.amount + e.fee;
          lots[code] = [...?lots[code], Lot(e.date, e.shares, cost)];
          byCode[code] = held.copyWith(
            shares: held.shares + e.shares,
            cost: held.cost + cost,
          );
        case EntryType.sell:
          final (part, rest) = _take(
            lots[code] ?? const [],
            e.shares,
            average: e.average,
          );
          lots[code] = rest;
          byCode[code] = held.copyWith(
            shares: held.shares - e.shares,
            cost: held.cost - part,
            realized: held.realized + e.amount - e.fee - e.tax - part,
          );
        case EntryType.dividend when e.isReduction:
          // A reduction takes away shares that must be there.
          if (-e.shares > held.shares) {
            throw StateError('減少的股數超過持有股數');
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
          byCode[code] = held.copyWith(
            shares: left,
            cost: held.cost - lowered - dropped,
            price: left == 0 ? held.price : worth / left,
            realized: held.realized + e.amount - lowered - dropped,
          );
        case EntryType.dividend when e.shares > 0 && held.shares > 0:
          // A split or a stock dividend: every lot grows, keeping its
          // cost and its date.
          final total = held.shares + e.shares;
          final (after, change) = _reratio(
            lots[code] ?? const [],
            total,
            held.shares,
            wholeShares: !e.split,
          );
          lots[code] = after;
          final dropped = change.droppedCost.toInt();
          byCode[code] = held.copyWith(
            shares: total,
            cost: held.cost - dropped,
            price: e.split ? held.price * held.shares / total : held.price,
            realized: held.realized - dropped,
            dividends: held.dividends + e.dividendNet,
          );
        case EntryType.dividend:
          // Shares given with nothing held start a lot of their own.
          if (e.shares > 0) {
            lots[code] = [...?lots[code], Lot(e.date, e.shares, 0)];
          }
          byCode[code] = held.copyWith(
            shares: held.shares + e.shares,
            dividends: held.dividends + e.dividendNet,
          );
        default:
          break;
      }
      } on StateError {
        if (!lenient) rethrow;
        continue;
      }
      final before = held.shares;
      final after = byCode[code]?.shares ?? before;
      final rescaled =
          e.type == EntryType.dividend &&
          before > 0 &&
          (e.split || e.isReduction);
      final kept = steps[code] ??= [];
      if (rescaled) {
        for (final (i, (d, n)) in kept.indexed) {
          kept[i] = (d, (n * after / before).round());
        }
      }
      kept.add((e.date, after));
    }
    final holdings = [
      for (final h in byCode.values)
        if (h.shares > 0 || h.realized != 0) h,
    ]..sort((a, b) => b.value.compareTo(a.value));
    return Portfolio._(List.unmodifiable(holdings), lots, steps);
  }

  /// Held stocks, and sold ones with a realised result, largest first.
  final List<Holding> holdings;

  final Map<String, List<Lot>> _lots;

  /// Each stock's shares after each trade, in date order; counts before a
  /// split or reduction are scaled to today's shares.
  final Map<String, List<(DateTime, int)>> _steps;

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

  /// The cost of selling [shares] out of [lots], and the lots left: the
  /// ledger's own rule, oldest lots first or at the average cost.
  static (int, List<Lot>) _take(
    List<Lot> lots,
    int shares, {
    required bool average,
  }) {
    final held = lots.fold(BigInt.zero, (sum, l) => sum + l.units);
    final selling = BigInt.from(shares) * unitsPerShare;
    if (selling > held) throw StateError('賣出股數超過持有股數');
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
