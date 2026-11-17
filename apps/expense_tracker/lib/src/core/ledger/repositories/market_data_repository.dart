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
