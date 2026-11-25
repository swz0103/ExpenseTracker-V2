import 'package:core/foundation_values.dart'
    show BoardSide, Currency, valuationSide;
import 'package:core/time/calendar_day.dart';
import 'package:core/fx/dated_figures.dart' show FigureOn, MarketHistory;

import '../models/models.dart'
    show homeCode, rateScale, roundedBigQuotient, scaledRate;

/// What the screens and queries may ask of the market data.
abstract interface class MarketDataReader {
  /// The trading day of the newest close the holdings are valued at;
  /// null when none was fetched yet.
  DateTime? get quotedOn;

  /// NT$ for one unit of each foreign currency: 臺灣銀行's spot buying
  /// rate. Empty until fetched; the map cannot be changed.
  Map<String, double> get rates;

  /// NT$ for one unit of each foreign currency: 臺灣銀行's spot selling
  /// rate, what is owed in it is valued at (D59). Empty until fetched,
  /// and for a board kept before the selling rates were; the map cannot
  /// be changed.
  Map<String, double> get sellRates;

  /// Each stock's change per share on its last trading day, by code; the
  /// map cannot be changed.
  Map<String, double> get moves;

  /// The trading day of each stock's kept close, by code; the map cannot
  /// be changed.
  Map<String, DateTime> get quoteDays;

  /// NT$ for one unit of [currency]; null without a rate.
  double? rateOf(String currency);

  /// [code]'s change per share on its last trading day; null without one.
  double? moveOf(String code);

  /// The day of [code]'s kept close when it is older than [quotedOn]: the
  /// last trading day of a stock not traded since, or a close kept from
  /// before when the latest could not be fetched. Null when it is the
  /// latest, or not known.
  DateTime? olderQuote(String code);

  /// [minor] units of [currency] in whole NT$ at [rates]; null without a
  /// rate for it.
  int? toHome(int minor, String currency);

  /// What a [balance] of [currency] is worth in whole NT$: held at the
  /// buying rate, owed at the selling rate (core's `valuationSide`, D59),
  /// the buying rate standing in for a selling rate not fetched yet;
  /// null without a rate.
  int? valueAtHome(int balance, String currency);

  /// [amount] of [from] in the smallest unit of [to], through NT$ at
  /// [rates]; null without a rate for either.
  int? convert(int amount, String from, String to);

  /// The rates and closes kept by day (D58).
  MarketHistory get history;

  /// [currency]'s rate on the [side] of the board for [day], by the one
  /// rule (`DatedFigures.on`, D58): that day's board, else the nearest
  /// earlier day's, else today's; null without any.
  FigureOn? rateOn(
    String currency,
    DateTime day, {
    BoardSide side = BoardSide.buying,
  });

  /// [code]'s close for [day], by the same rule: that day's, else the
  /// nearest earlier day's, else the latest kept; null without any.
  FigureOn? closeOn(String code, DateTime day);

  /// [toHome] at the buying rate for [day] ([rateOn]).
  int? toHomeOn(int minor, String currency, DateTime day);

  /// [valueAtHome] at the rates for [day] ([rateOn]): held at the buying
  /// rate, owed at the selling rate, the buying rate standing in for a
  /// selling rate not known.
  int? valueAtHomeOn(int balance, String currency, DateTime day);

  /// [convert] at the buying rates for [day] ([rateOn]).
  int? convertOn(int amount, String from, String to, DateTime day);
}

/// The rates, the day's changes and the quote days last fetched. Only
/// fetching new ones writes it; the screens see a [MarketDataReader].
final class MarketDataRepository implements MarketDataReader {
  MarketDataRepository({
    Map<String, double> rates = const {},
    Map<String, double> sellRates = const {},
    Map<String, double> moves = const {},
    this._quotedOn,
    Map<String, DateTime> quoteDays = const {},
    MarketHistory? history,
  }) : _history = history ?? MarketHistory(),
       _rates = {...rates},
       _sellRates = {...sellRates},
       _moves = {...moves},
       _quoteDays = {...quoteDays};

  final Map<String, double> _rates;
  final Map<String, double> _sellRates;
  final Map<String, double> _moves;
  DateTime? _quotedOn;
  final Map<String, DateTime> _quoteDays;
  MarketHistory _history;

  @override
  DateTime? get quotedOn => _quotedOn;

  @override
  MarketHistory get history => _history;

  @override
  FigureOn? rateOn(
    String currency,
    DateTime day, {
    BoardSide side = BoardSide.buying,
  }) =>
      switch (side) {
        BoardSide.buying => _history.buying,
        BoardSide.selling => _history.selling,
      }.on(
        currency,
        BusinessDate.of(day),
        today: switch (side) {
          BoardSide.buying => _rates[currency],
          BoardSide.selling => _sellRates[currency],
        },
      );

  @override
  FigureOn? closeOn(String code, DateTime day) =>
      _history.closes.on(code, BusinessDate.of(day));

  @override
  int? toHomeOn(int minor, String currency, DateTime day) =>
      _atRate(minor, currency, rateOn(currency, day)?.figure);

  @override
  int? valueAtHomeOn(int balance, String currency, DateTime day) {
    final buying = rateOn(currency, day)?.figure;
    return _atRate(balance, currency, switch (valuationSide(balance)) {
      BoardSide.buying => buying,
      BoardSide.selling =>
        rateOn(currency, day, side: BoardSide.selling)?.figure ?? buying,
    });
  }

  @override
  int? convertOn(int amount, String from, String to, DateTime day) =>
      _converted(amount, from, to, (c) => rateOn(c, day)?.figure);

  @override
  Map<String, double> get rates => Map.unmodifiable(_rates);

  @override
  Map<String, double> get sellRates => Map.unmodifiable(_sellRates);

  @override
  Map<String, double> get moves => Map.unmodifiable(_moves);

  @override
  Map<String, DateTime> get quoteDays => Map.unmodifiable(_quoteDays);

  @override
  double? rateOf(String currency) => _rates[currency];

  @override
  double? moveOf(String code) => _moves[code];

  @override
  DateTime? olderQuote(String code) {
    final day = _quoteDays[code];
    final latest = _quotedOn;
    if (day == null || latest == null || !day.isBefore(latest)) return null;
    return day;
  }

  @override
  int? toHome(int minor, String currency) =>
      _atRate(minor, currency, _rates[currency]);

  @override
  int? valueAtHome(int balance, String currency) =>
      _atRate(balance, currency, switch (valuationSide(balance)) {
        BoardSide.buying => _rates[currency],
        BoardSide.selling => _sellRates[currency] ?? _rates[currency],
      });

  int? _atRate(int minor, String currency, double? rate) {
    if (currency == homeCode) return minor;
    if (rate == null) return null;
    // minor / unit × rate, in whole numbers.
    return roundedBigQuotient(
      BigInt.from(minor) * scaledRate(rate),
      BigInt.from(_unit(currency) * rateScale),
    );
  }

  @override
  int? convert(int amount, String from, String to) =>
      _converted(amount, from, to, (c) => _rates[c]);

  int? _converted(
    int amount,
    String from,
    String to,
    double? Function(String currency) rateOf,
  ) {
    if (from == to) return amount;
    if (to == homeCode) return _atRate(amount, from, rateOf(from));
    final into = rateOf(to);
    if (into == null || into <= 0) return null;
    // NT$ per unit of [from] (one for NT$ itself), over NT$ per unit of
    // [to], in whole numbers: amount / unit(from) × rate(from) / rate(to)
    // × unit(to).
    final BigInt fromRate;
    if (from == homeCode) {
      fromRate = BigInt.from(rateScale);
    } else {
      final rate = rateOf(from);
      if (rate == null) return null;
      fromRate = scaledRate(rate);
    }
    return roundedBigQuotient(
      BigInt.from(amount) * fromRate * BigInt.from(_unit(to)),
      BigInt.from(_unit(from)) * scaledRate(into),
    );
  }

  static int _unit(String currency) =>
      Currency.scaleOf(currency) == 0 ? 1 : 100;

  /// Takes everything fetched anew, in place of what was kept.
  void replace({
    required Map<String, double> rates,
    Map<String, double> sellRates = const {},
    required Map<String, double> moves,
    required DateTime? quotedOn,
    required Map<String, DateTime> quoteDays,
    MarketHistory? history,
  }) {
    // Copied first: the maps given may be this repository's own.
    final (r, s, m, d) = (
      {...rates},
      {...sellRates},
      {...moves},
      {...quoteDays},
    );
    _rates
      ..clear()
      ..addAll(r);
    _sellRates
      ..clear()
      ..addAll(s);
    _moves
      ..clear()
      ..addAll(m);
    _quoteDays
      ..clear()
      ..addAll(d);
    _quotedOn = quotedOn;
    _history = history ?? MarketHistory();
  }

  /// Takes what [other] holds, as when the book is read again.
  void replaceWith(MarketDataReader other) => replace(
    rates: other.rates,
    sellRates: other.sellRates,
    moves: other.moves,
    quotedOn: other.quotedOn,
    quoteDays: other.quoteDays,
    history: other.history,
  );
}
