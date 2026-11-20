import 'dart:collection';

import '../models/models.dart';
import '../portfolio.dart';

/// What the screens and queries may ask of the holdings.
abstract interface class HoldingReader {
  /// The holdings replayed from the starting positions and every trade,
  /// with the day's change where a close gave one; the list cannot be
  /// changed.
  List<Holding> get all;

  /// The holding of [code]; null when none is held or quoted.
  Holding? byCode(String code);

  /// Whether [code] has a fetched close, rather than the price it was last
  /// bought at standing in for one.
  bool hasQuote(String code);

  /// The lots of [code] still held, oldest first.
  List<Lot> lotsOf(String code);

  /// What selling [shares] of [code] now would cost: the oldest lots
  /// first, or the average price.
  int saleCost(String code, int shares, {bool average = false});

  /// The shares of [code] held at the end of [day], in today's shares.
  int sharesOn(String code, DateTime day);

  /// Whether [entries] can be the book's: none of their trades sells more
  /// shares than are held by then.
  bool holdsWith(List<Entry> entries);

  /// What the holdings are worth at their reference closes.
  int get marketValue;

  /// What the shares still held cost.
  int get costBasis;

  /// The holdings' change in value on their last trading day.
  int get dayChange;

  /// Profit or loss of shares already sold.
  int get realizedGain;

  /// Dividends received so far.
  int get dividends;
}

/// The starting positions, with the stocks' reference prices and names,
/// and the holdings replayed from them and the trades. The screens see a
/// [HoldingReader].
final class HoldingRepository implements HoldingReader {
  /// [_moveOf] gives a stock's change per share on its last trading day;
  /// the holdings are replayed by [replay] before they are first read.
  HoldingRepository(Iterable<Holding> start, {required this._moveOf})
    : _start = [...start];

  final List<Holding> _start;
  final double? Function(String code) _moveOf;
  Portfolio? _portfolio;
  List<Holding>? _withChanges;

  Portfolio get _replayed =>
      _portfolio ?? (throw StateError('holdings read before replay'));

  /// The starting positions, as fetched and kept.
  List<Holding> get start => List.unmodifiable(_start);

  @override
  List<Holding> get all => UnmodifiableListView(
    // Built anew rather than changed, so a view handed out stays as it was.
    _withChanges ??= [
      for (final h in _replayed.holdings)
        if (_moveOf(h.code) case final move?)
          h.withChange(timesPrice(h.shares, move))
        else
          h,
    ],
  );

  @override
  Holding? byCode(String code) {
    for (final h in all) {
      if (h.code == code) return h;
    }
    return null;
  }

  @override
  int get marketValue => all.fold(0, (sum, h) => sum + h.value);

  @override
  int get costBasis => all.fold(0, (sum, h) => sum + h.cost);

  @override
  int get dayChange => all.fold(0, (sum, h) => sum + h.change);

  @override
  int get realizedGain => all.fold(0, (sum, h) => sum + h.realized);

  @override
  int get dividends => all.fold(0, (sum, h) => sum + h.dividends);

  @override
  bool hasQuote(String code) => _start.any((h) => h.code == code);

  @override
  List<Lot> lotsOf(String code) => _replayed.lotsOf(code);

  @override
  int saleCost(String code, int shares, {bool average = false}) =>
      _replayed.saleCost(code, shares, average: average);

  @override
  int sharesOn(String code, DateTime day) => _replayed.sharesOn(code, day);

  @override
  bool holdsWith(List<Entry> entries) {
    try {
      Portfolio.replay(_start, entries);
      return true;
    } on StateError {
      // A book that would leave a sale short of shares is refused.
      return false;
    }
  }

  /// Works the holdings out again from the starting positions and the
  /// trades of [entries]. An oversold trade throws a [StateError] and
  /// leaves the holdings as they were; with [lenient], as for a book just
  /// read, it is left out instead.
  void replay(List<Entry> entries, {bool lenient = false}) {
    _portfolio = Portfolio.replay(_start, entries, lenient: lenient);
    _withChanges = null;
  }

  /// Takes new starting positions; [replay] follows before the holdings
  /// are read again.
  void replaceStart(Iterable<Holding> start) {
    final copy = [...start];
    _start
      ..clear()
      ..addAll(copy);
    _withChanges = null;
  }
}
