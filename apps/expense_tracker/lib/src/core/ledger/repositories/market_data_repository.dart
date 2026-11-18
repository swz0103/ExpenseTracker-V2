import 'package:core/foundation_values.dart' show Currency;

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

  /// [amount] of [from] in the smallest unit of [to], through NT$ at
  /// [rates]; null without a rate for either.
  int? convert(int amount, String from, String to);
}

/// The rates, the day's changes and the quote days last fetched. Only
/// fetching new ones writes it; the screens see a [MarketDataReader].
final class MarketDataRepository implements MarketDataReader {
  MarketDataRepository({
    Map<String, double> rates = const {},
    Map<String, double> moves = const {},
    this._quotedOn,
    Map<String, DateTime> quoteDays = const {},
  }) : _rates = {...rates},
       _moves = {...moves},
       _quoteDays = {...quoteDays};

  final Map<String, double> _rates;
  final Map<String, double> _moves;
  DateTime? _quotedOn;
  final Map<String, DateTime> _quoteDays;

  @override
  DateTime? get quotedOn => _quotedOn;

  @override
  Map<String, double> get rates => Map.unmodifiable(_rates);

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
  int? toHome(int minor, String currency) {
    if (currency == homeCode) return minor;
    final rate = _rates[currency];
    if (rate == null) return null;
    // minor / unit × rate, in whole numbers.
    return roundedBigQuotient(
      BigInt.from(minor) * scaledRate(rate),
      BigInt.from(_unit(currency) * rateScale),
    );
  }

  @override
  int? convert(int amount, String from, String to) {
    if (from == to) return amount;
    if (to == homeCode) return toHome(amount, from);
    final into = _rates[to];
    if (into == null || into <= 0) return null;
    // NT$ per unit of [from] (one for NT$ itself), over NT$ per unit of
    // [to], in whole numbers: amount / unit(from) × rate(from) / rate(to)
    // × unit(to).
    final BigInt fromRate;
    if (from == homeCode) {
      fromRate = BigInt.from(rateScale);
    } else {
      final rate = _rates[from];
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
    required Map<String, double> moves,
    required DateTime? quotedOn,
    required Map<String, DateTime> quoteDays,
  }) {
    // Copied first: the maps given may be this repository's own.
    final (r, m, d) = ({...rates}, {...moves}, {...quoteDays});
    _rates
      ..clear()
      ..addAll(r);
    _moves
      ..clear()
      ..addAll(m);
    _quoteDays
      ..clear()
      ..addAll(d);
    _quotedOn = quotedOn;
  }

  /// Takes what [other] holds, as when the book is read again.
  void replaceWith(MarketDataReader other) => replace(
    rates: other.rates,
    moves: other.moves,
    quotedOn: other.quotedOn,
    quoteDays: other.quoteDays,
  );
}
