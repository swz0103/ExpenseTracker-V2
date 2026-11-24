import 'package:core/money/price.dart' show timesPrice;
import 'package:domain/investments.dart' show HoldingStatus, holdingStatus;

import 'dart:collection';

import '../models/models.dart';
import '../portfolio.dart';

/// The holdings split by [holdingStatus]: the one filter every list and
/// count of holdings uses.
extension HoldingsByStatus on HoldingReader {
  /// The stocks with shares still held.
  List<Holding> get held => [
    for (final h in all)
      if (holdingStatus(h.shares) == HoldingStatus.held) h,
  ];

  /// The stocks sold to the last share, kept for their history.
  List<Holding> get soldOut => [
    for (final h in all)
      if (holdingStatus(h.shares) == HoldingStatus.soldOut) h,
  ];
}

/// What the screens and queries may ask of the holdings.
abstract interface class HoldingReader {
  /// The holdings replayed from the starting positions and every trade,
  /// with the day's change where a close gave one; the list cannot be
  /// changed.
  List<Holding> get all;

  /// The holding of [code]; null when none is held or quoted.
  Holding? byCode(String code);

  /// Every stock held from the start or traded, as the trades leave it,
  /// those [all] does not list included: what the journal's postings are
  /// compared with.
  List<Holding> get every;

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

  /// What selling [shares] of [code] would cost after the trades of
  /// [entries] alone, from the starting positions: the lots held then,
  /// not today. Null when fewer shares were held.
  int? saleCostWith(
    List<Entry> entries,
    String code,
    int shares, {
    bool average = false,
  });

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
  /// [_moveOf] gives a stock's change per share on its last trading day
  /// and [_quoteDayOf] that day, so shares bought after it are not counted
  /// in its change; the holdings are replayed by [replay] before they are
  /// first read.
  HoldingRepository(
    Iterable<Holding> start, {
    required this._moveOf,
    DateTime? Function(String code)? quoteDayOf,
  }) : _start = [...start],
       _quoteDayOf = quoteDayOf ?? ((_) => null);

  final List<Holding> _start;
  final double? Function(String code) _moveOf;
  final DateTime? Function(String code) _quoteDayOf;
  Portfolio? _portfolio;
  List<Holding>? _withChanges;

  Portfolio get _replayed =>
      _portfolio ?? (throw StateError('holdings read before replay'));

  /// The starting positions, as fetched and kept.
  List<Holding> get start => List.unmodifiable(_start);

  @override
  List<Holding> get every => _replayed.every;

  @override
  List<Holding> get all => UnmodifiableListView(
    // Built anew rather than changed, so a view handed out stays as it was.
    _withChanges ??= [
      for (final h in _replayed.holdings)
        if (_moveOf(h.code) case final move?)
          h.withChange(timesPrice(_sharesOnQuoteDay(h), move))
        else
          h,
    ],
  );

  /// The shares of [h] held at the end of its quote's trading day: those
  /// bought later did not move with it.
  int _sharesOnQuoteDay(Holding h) => switch (_quoteDayOf(h.code)) {
    final day? => _replayed.sharesOn(h.code, day),
    null => h.shares,
  };

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

  /// The trades the holdings leave out, by id: sales and reductions an
  /// older version let take more shares than were held.
  List<String> get leftOut => _replayed.leftOut;

  @override
  int saleCost(String code, int shares, {bool average = false}) =>
      _replayed.saleCost(code, shares, average: average);

  @override
  int sharesOn(String code, DateTime day) => _replayed.sharesOn(code, day);

  @override
  int? saleCostWith(
    List<Entry> entries,
    String code,
    int shares, {
    bool average = false,
  }) {
    final then = Portfolio.replay(_start, entries, lenient: true);
    var held = 0;
    for (final h in then.holdings) {
      if (h.code == code) held = h.shares;
    }
    if (shares > held) return null;
    return then.saleCost(code, shares, average: average);
  }

  @override
  bool holdsWith(List<Entry> entries) => _newlyShort(entries) == null;

  /// The trades an old book let take more shares than were held, left out
  /// as it was read ([replay] with `lenient`): kept as they are, never
  /// held against a later change (D47). Any other short trade is.
  final _tolerated = <String>{};

  /// The first trade of [entries], in date order, short of shares that
  /// the book did not already hold short as it was read; null when none.
  Entry? _newlyShort(List<Entry> entries) {
    final short = Portfolio.replay(_start, entries, lenient: true).leftOut;
    for (final id in short) {
      if (!_tolerated.contains(id)) {
        return entries.firstWhere((e) => e.id == id);
      }
    }
    return null;
  }

  /// Works the holdings out again from the starting positions and the
  /// trades of [entries] that count on [today] ([countsOn]): a trade an
  /// old book dated later, written before such trades were refused (D70),
  /// joins on its day, when the ledger's day check replays again. An oversold
  /// trade throws a [StateError] and leaves the holdings as they were,
  /// one dated later included, so no change leaves a later sale short;
  /// with [lenient], as for a book just read, it is left out instead, and
  /// stays left out by every later replay ([_tolerated]): a change beside
  /// it is held only to the trades it makes short itself.
  void replay(
    List<Entry> entries, {
    required DateTime today,
    bool lenient = false,
  }) {
    if (lenient) return adopt(readHoldings(_start, entries, today));
    if (_newlyShort(entries) case final short?) {
      // Every trade, the later ones too, must hold together; an old
      // book's short trade, left out as it was read, stays left out.
      throw OversoldTrade(short);
    }
    final counted = countedOn(entries, today).toList();
    _portfolio = Portfolio.replay(_start, counted, lenient: true);
    _withChanges = null;
  }

  /// Takes [read] as the holdings: a book read elsewhere ([readHoldings],
  /// on the book's worker as it opens, D51), as [replay] with `lenient`.
  void adopt(ReadHoldings read) {
    _tolerated
      ..clear()
      ..addAll(read.tolerated);
    _portfolio = read.portfolio;
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

/// The holdings of a book just read, and the trades it held short.
typedef ReadHoldings = ({Portfolio portfolio, Set<String> tolerated});

/// The holdings of a book just read: replayed from [start] and the trades
/// of [entries] that count on [today], every short trade left out; and
/// those, kept as they are from then on ([HoldingRepository.adopt]). Pure
/// values, so the book's worker works them out as it opens (D51).
ReadHoldings readHoldings(
  List<Holding> start,
  List<Entry> entries,
  DateTime today,
) {
  final all = Portfolio.replay(start, entries, lenient: true);
  final counted = countedOn(entries, today).toList();
  return (
    portfolio: counted.length == entries.length
        ? all
        : Portfolio.replay(start, counted, lenient: true),
    tolerated: {...all.leftOut},
  );
}
