import 'dart:math';

import 'records.dart';

/// Holdings replayed from starting positions and investment entries:
/// each stock's lots and what they cost, and how many shares were held
/// after each trade. The same inputs always give the same portfolio.
final class Portfolio {
  Portfolio._(this.holdings, this._lots, this._steps);

  /// Replays the trades of [entries] over the [start] positions, in date
  /// order and in the order written within a day. An oversold trade
  /// throws a [StateError].
  factory Portfolio.replay(List<Holding> start, List<Entry> entries) {
    final opening = DateTime.utc(2025);
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
        case EntryType.dividend when e.isReduction && held.shares > 0:
          final left = max(0, held.shares + e.shares);
          final lowered = min(e.amount, held.cost);
          final scaled = _scaled(lots[code] ?? const [], left);
          lots[code] = _lowered(scaled, lowered);
          final worth = max(0.0, held.price * held.shares - e.amount);
          byCode[code] = held.copyWith(
            shares: left,
            cost: held.cost - lowered,
            price: left == 0 ? held.price : worth / left,
            realized: held.realized + e.amount - lowered,
          );
        case EntryType.dividend when e.split && held.shares > 0:
          final ratio = (held.shares + e.shares) / held.shares;
          lots[code] = _scaled(lots[code] ?? const [], held.shares + e.shares);
          byCode[code] = held.copyWith(
            shares: held.shares + e.shares,
            price: held.price / ratio,
            dividends: held.dividends + e.dividendNet,
          );
        case EntryType.dividend:
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

  /// The cost of selling [shares] out of [lots], and the lots left.
  static (int, List<Lot>) _take(
    List<Lot> lots,
    int shares, {
    required bool average,
  }) {
    final held = lots.fold(0, (sum, l) => sum + l.shares);
    if (shares > held) throw StateError('賣出股數超過持有股數');
    if (average) {
      final cost = lots.fold(0, (sum, l) => sum + l.cost);
      final part = held == 0 ? 0 : (cost * shares / held).round();
      final left = held - shares;
      return (
        part,
        left == 0 ? <Lot>[] : [Lot(lots.last.date, left, cost - part)],
      );
    }
    var need = shares;
    var part = 0;
    final rest = <Lot>[];
    for (final lot in lots) {
      if (need == 0) {
        rest.add(lot);
      } else if (lot.shares <= need) {
        part += lot.cost;
        need -= lot.shares;
      } else {
        final piece = (lot.cost * need / lot.shares).round();
        part += piece;
        rest.add(Lot(lot.date, lot.shares - need, lot.cost - piece));
        need = 0;
      }
    }
    return (part, rest);
  }

  /// [lots] with their shares grown to [total] in proportion, each at its
  /// own cost; the last takes what rounding leaves.
  static List<Lot> _scaled(List<Lot> lots, int total) {
    final held = lots.fold(0, (sum, l) => sum + l.shares);
    if (held == 0) return lots;
    var left = total;
    final scaled = <Lot>[];
    for (final (i, l) in lots.indexed) {
      final last = i == lots.length - 1;
      final shares = last ? left : (l.shares * total / held).round();
      left -= shares;
      scaled.add(Lot(l.date, shares, l.cost));
    }
    return scaled;
  }

  /// [lots] with [amount] taken off their cost in proportion to it; the
  /// last takes what rounding leaves.
  static List<Lot> _lowered(List<Lot> lots, int amount) {
    final total = lots.fold(0, (sum, l) => sum + l.cost);
    if (total == 0 || amount == 0) return lots;
    var left = amount;
    final lowered = <Lot>[];
    for (final (i, l) in lots.indexed) {
      final part = i == lots.length - 1 ? left : amount * l.cost ~/ total;
      left -= part;
      lowered.add(Lot(l.date, l.shares, l.cost - part));
    }
    return lowered;
  }
}
