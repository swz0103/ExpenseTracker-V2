import 'dart:async';
import 'dart:convert';

import 'package:foundation_values/foundation_values.dart';
import 'package:investments/investments.dart';

/// Every value here is informational. What was actually traded or
/// converted is what the user books.
enum MarketState { available, stale, missing, unsupported, failed }

final class MarketResult<T> {
  const MarketResult(this.state, {this.value, this.reason});

  final MarketState state;
  final T? value;

  /// Why the value is not [MarketState.available]; not for display.
  final String? reason;
}

/// One day's closing price from TWSE or TPEx.
final class StockClose {
  const StockClose({
    required this.symbol,
    required this.decimalPrice,
    required this.asOf,
    required this.fetchedAt,
  });

  final String symbol;

  /// Exact positive NT$ price per share, as published; never a double.
  final String decimalPrice;
  final BusinessDate asOf;
  final UtcInstant fetchedAt;
}

/// Bank of Taiwan's board rates for one currency, in NT$ per unit. A rate
/// the bank does not quote, such as cash for some currencies, is null.
final class BankRate {
  const BankRate({
    required this.currency,
    this.cashBuy,
    this.cashSell,
    this.spotBuy,
    this.spotSell,
  });

  final Currency currency;
  final FxRate? cashBuy;
  final FxRate? cashSell;
  final FxRate? spotBuy;
  final FxRate? spotSell;

  /// What the bank pays for this currency in an account: the value of a
  /// foreign-currency balance in NT$.
  FxRate? get valuation => spotBuy ?? cashBuy;
}

/// The day's board, one row per quoted currency.
final class BankRates {
  BankRates({
    required this.asOf,
    required this.fetchedAt,
    required Map<String, BankRate> rates,
  }) : rates = Map.unmodifiable(rates);

  /// The Taipei date the board was fetched on; the bank publishes daily.
  final BusinessDate asOf;
  final UtcInstant fetchedAt;
  final Map<String, BankRate> rates;

  BankRate? operator [](Currency currency) => rates[currency.code];
}

final class MarketResponse {
  const MarketResponse(this.statusCode, this.body);

  final int statusCode;
  final String body;
}

abstract interface class MarketTransport {
  Future<MarketResponse> get(Uri uri);
}

/// Largest response body accepted, in characters. TPEx's daily snapshot is
/// over 2 MiB.
const marketResponseLimit = 8 * 1024 * 1024;

/// Daily closing prices (TWSE, TPEx) and Bank of Taiwan board rates: one
/// free source each, no account needed. A snapshot is fetched once and
/// shared by every holding; requests in flight are shared, and a failure
/// is not retried for [retryAfter], falling back to the last snapshot as
/// stale.
final class MarketDataGateway {
  MarketDataGateway({
    required MarketTransport transport,
    DateTime Function()? clock,
    this.cacheTtl = const Duration(minutes: 20),
    this.retryAfter = const Duration(minutes: 1),
    this.maximumObservationAge = const Duration(days: 4),
  }) : _transport = transport,
       _clock = clock ?? DateTime.now {
    if (cacheTtl <= Duration.zero ||
        retryAfter < Duration.zero ||
        maximumObservationAge < Duration.zero) {
      throw ArgumentError('Invalid market data time policy');
    }
  }

  static final twseUri = Uri.https(
    'openapi.twse.com.tw',
    '/v1/exchangeReport/STOCK_DAY_ALL',
  );
  static final tpexUri = Uri.https(
    'www.tpex.org.tw',
    '/openapi/v1/tpex_mainboard_daily_close_quotes',
  );
  static final bankRatesUri = Uri.https('rate.bot.com.tw', '/xrt/flcsv/0/day');

  final MarketTransport _transport;
  final DateTime Function() _clock;
  final Duration cacheTtl;
  final Duration retryAfter;
  final Duration maximumObservationAge;
  final _cache = <Uri, _Snapshot>{};
  final _failedAt = <Uri, DateTime>{};
  final _pending = <Uri, Future<_Fetch>>{};

  /// The latest close of a TWSE or TPEx stock or ETF traded in NT$.
  Future<MarketResult<StockClose>> stockClose(
    InvestmentInstrument instrument,
  ) async {
    final (uri, codeKey, priceKey) = switch (instrument.marketCode) {
      'TWSE' => (twseUri, 'Code', 'ClosingPrice'),
      'TPEX' => (tpexUri, 'SecuritiesCompanyCode', 'Close'),
      _ => (null, '', ''),
    };
    if (uri == null ||
        instrument.tradingCurrency != _twd ||
        !_symbol(instrument).hasMatch(instrument.symbol)) {
      return const MarketResult(
        MarketState.unsupported,
        reason: 'Only TWSE and TPEx stocks and ETFs in NT\$',
      );
    }
    final fetched = await _fetch(uri);
    final snapshot = fetched.snapshot;
    if (snapshot == null) {
      return MarketResult(fetched.state, reason: fetched.reason);
    }
    try {
      final row = snapshot.row(codeKey, instrument.symbol);
      if (row == null) {
        return const MarketResult(MarketState.missing, reason: 'Not listed');
      }
      final price = _positiveDecimal(row[priceKey]);
      if (price == null) {
        return const MarketResult(MarketState.missing, reason: 'No trade');
      }
      final asOf = _rocDate(row['Date']);
      final close = StockClose(
        symbol: instrument.symbol,
        decimalPrice: price,
        asOf: asOf,
        fetchedAt: snapshot.fetchedAt,
      );
      final stale = fetched.state == MarketState.stale || _old(asOf);
      return MarketResult(
        stale ? MarketState.stale : MarketState.available,
        value: close,
        reason: stale ? fetched.reason ?? 'Old observation' : null,
      );
    } on FormatException {
      return const MarketResult(MarketState.failed, reason: 'Bad snapshot');
    }
  }

  /// Today's Bank of Taiwan board.
  Future<MarketResult<BankRates>> bankRates() async {
    final fetched = await _fetch(bankRatesUri);
    final snapshot = fetched.snapshot;
    if (snapshot == null) {
      return MarketResult(fetched.state, reason: fetched.reason);
    }
    try {
      final rates = snapshot.bankRates ??= _parseBankRates(snapshot);
      return MarketResult(fetched.state, value: rates, reason: fetched.reason);
    } on FormatException {
      return const MarketResult(MarketState.failed, reason: 'Bad board');
    } on FxException {
      return const MarketResult(MarketState.failed, reason: 'Bad rate');
    }
  }

  bool _old(BusinessDate asOf) {
    final today = _taipeiDate(_clock());
    final age = _epochDay(today) - _epochDay(asOf);
    return age < 0 || age > maximumObservationAge.inDays;
  }

  Future<_Fetch> _fetch(Uri uri) {
    final now = _clock().toUtc();
    final cached = _cache[uri];
    if (cached != null &&
        !now.isBefore(cached.fetchedAt.value) &&
        now.difference(cached.fetchedAt.value) < cacheTtl) {
      return Future.value(_Fetch(cached, MarketState.available));
    }
    final inFlight = _pending[uri];
    if (inFlight != null) return inFlight;
    final failed = _failedAt[uri];
    if (failed != null && now.difference(failed) < retryAfter) {
      return Future.value(_fallback(cached, 'Retrying later'));
    }
    final future = _request(uri, cached, UtcInstant(now));
    _pending[uri] = future;
    return future.whenComplete(() => _pending.remove(uri));
  }

  Future<_Fetch> _request(Uri uri, _Snapshot? prior, UtcInstant now) async {
    try {
      final response = await _transport.get(uri);
      if (response.statusCode == 200 &&
          response.body.length <= marketResponseLimit) {
        final snapshot = _Snapshot(response.body, now);
        _cache[uri] = snapshot;
        _failedAt.remove(uri);
        return _Fetch(snapshot, MarketState.available);
      }
    } on Object {
      // A network failure is reported like a bad status below.
    }
    _failedAt[uri] = now.value;
    return _fallback(prior, 'Request failed');
  }

  static _Fetch _fallback(_Snapshot? prior, String reason) => _Fetch(
    prior,
    prior == null ? MarketState.failed : MarketState.stale,
    reason,
  );

  BankRates _parseBankRates(_Snapshot snapshot) {
    final body = snapshot.body.replaceFirst('\uFEFF', '');
    final lines = [
      for (final line in const LineSplitter().convert(body))
        if (line.trim().isNotEmpty) line,
    ];
    if (lines.isEmpty || !lines.first.startsWith('幣別')) {
      throw const FormatException('Not a Bank of Taiwan board');
    }
    final rates = <String, BankRate>{};
    for (final line in lines.skip(1)) {
      final cells = [for (final cell in line.split(',')) cell.trim()];
      // Columns: code, 本行買入, cash, spot, 7 forwards, 本行賣出, cash,
      // spot, 7 forwards.
      if (cells.length < 14 || cells[1] != '本行買入' || cells[11] != '本行賣出') {
        throw const FormatException('Unexpected board row');
      }
      final Currency currency;
      try {
        currency = Currency.of(cells[0]);
      } on MoneyException {
        continue; // A currency this app does not use.
      }
      if (currency == _twd || rates.containsKey(currency.code)) {
        throw const FormatException('Unexpected board currency');
      }
      FxRate? rate(int column) {
        final decimal = _positiveDecimal(cells[column]);
        return decimal == null ? null : FxRate.parse(currency, _twd, decimal);
      }

      rates[currency.code] = BankRate(
        currency: currency,
        cashBuy: rate(2),
        cashSell: rate(12),
        spotBuy: rate(3),
        spotSell: rate(13),
      );
    }
    return BankRates(
      asOf: _taipeiDate(snapshot.fetchedAt.value),
      fetchedAt: snapshot.fetchedAt,
      rates: rates,
    );
  }
}

final class _Fetch {
  const _Fetch(this.snapshot, this.state, [this.reason]);

  final _Snapshot? snapshot;
  final MarketState state;
  final String? reason;
}

/// One fetched body, decoded at most once per use: rows by symbol for
/// the exchanges, the parsed board for the bank.
final class _Snapshot {
  _Snapshot(this.body, this.fetchedAt);

  final String body;
  final UtcInstant fetchedAt;
  Map<String, Map<String, Object?>>? _rows;
  BankRates? bankRates;

  /// The row for [symbol]; a symbol listed twice makes the snapshot
  /// unusable for it.
  Map<String, Object?>? row(String key, String symbol) {
    final rows = _rows ??= _index(key);
    final row = rows[symbol];
    if (identical(row, _duplicate)) {
      throw const FormatException('Duplicate symbol');
    }
    return row;
  }

  Map<String, Map<String, Object?>> _index(String key) {
    final decoded = jsonDecode(body);
    if (decoded is! List) throw const FormatException('Expected rows');
    final rows = <String, Map<String, Object?>>{};
    for (final row in decoded) {
      if (row is! Map<String, Object?>) {
        throw const FormatException('Invalid row');
      }
      final symbol = row[key];
      if (symbol is! String) continue;
      rows[symbol] = rows.containsKey(symbol) ? _duplicate : row;
    }
    return rows;
  }
}

const Map<String, Object?> _duplicate = {};

final _twd = Currency.of('TWD');

/// Ordinary and preferred shares (2881A); ETFs including bond, leveraged
/// and inverse ones (00679B, 00631L, 00632R).
RegExp _symbol(InvestmentInstrument instrument) => switch (instrument.kind) {
  InstrumentKind.stock => RegExp(r'^[1-9][0-9]{3}[A-Z]?$'),
  InstrumentKind.etf => RegExp(r'^00[0-9]{2,4}[A-Z]?$'),
};

BusinessDate _taipeiDate(DateTime instant) {
  final local = instant.toUtc().add(const Duration(hours: 8));
  return BusinessDate(local.year, local.month, local.day);
}

int _epochDay(BusinessDate date) {
  final instant = DateTime.utc(date.year, date.month, date.day);
  return instant.millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;
}

BusinessDate _rocDate(Object? value) {
  if (value is! String || !RegExp(r'^[0-9]{7}$').hasMatch(value)) {
    throw const FormatException('Invalid ROC date');
  }
  return BusinessDate(
    int.parse(value.substring(0, 3)) + 1911,
    int.parse(value.substring(3, 5)),
    int.parse(value.substring(5, 7)),
  );
}

/// Decimal text with optional thousands separators; null for "no value"
/// markers and zero.
String? _positiveDecimal(Object? value) {
  if (value is! String) throw const FormatException('Expected decimal text');
  final text = value.trim();
  if (text.isEmpty || text == '--' || text == 'X' || text == '-') return null;
  if (text.length > 64 || !_decimal.hasMatch(text)) {
    throw const FormatException('Invalid decimal');
  }
  final clean = text.replaceAll(',', '');
  if (BigInt.parse(clean.replaceAll('.', '')) == BigInt.zero) return null;
  return clean;
}

final _decimal = RegExp(
  r'^(?:[0-9]+|[1-9][0-9]{0,2}(?:,[0-9]{3})+)(?:\.[0-9]{1,12})?$',
);
