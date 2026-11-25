import 'package:core/foundation_values.dart' show YearMonth;

import 'package:core/money/amount_parser.dart' show parseDecimal;
import 'package:flutter/foundation.dart' show Listenable;
import 'package:market/market_data.dart';

import '../../../core/platform/sync_job.dart';
import '../../../core/ledger/ledger.dart';
import '../../../core/ledger/persistence/sql_ledger_data_source.dart';
import '../../../core/messages/market_messages.dart';
import 'price_months.dart';

import 'package:core/time/utc_days.dart';

/// Closing prices and exchange rates for a ledger, fetched at most every
/// 20 minutes: when the ledger opens, when the app comes back, and at
/// once when a stock without a close is bought. A stock the exchanges do
/// not quote is named rather than left to look like it has a value.
final class MarketFeed extends SyncJob implements PriceHistory {
  /// Fetches for the ledger whose [_holdings] it reads and sets with
  /// [_commands], and whose [_changes] tell it a new stock was bought.
  MarketFeed(
    this._journal, {
    required this._changes,
    required this._holdings,
    required this._commands,
    required this._today,
    super.clock,
    this.kept,
  }) : super('收盤價與匯率', gap: const Duration(minutes: 20)) {
    _changes.addListener(_changed);
  }

  final SqlLedgerDataSource _journal;
  final Listenable _changes;
  final HoldingReader _holdings;
  final HoldingCommands _commands;

  /// The ledger's today, read each time.
  final DateTime Function() _today;

  /// Where finished months of daily closes are kept, sealed, so a
  /// holding's chart asks the exchanges only for what it has not seen;
  /// none in tests.
  final PriceMonths? kept;

  /// Each code's months of closes, by `yyyy-mm`: those [kept] and those
  /// read this run.
  final _months = <String, Map<String, List<(DateTime, double)>>>{};

  /// [kept] read into [_months] and [_otc], once.
  Future<void>? _loaded;

  Future<void> _load() async {
    final codes = await kept?.read() ?? const <String, CodeMonths>{};
    for (final MapEntry(:key, :value) in codes.entries) {
      _months.putIfAbsent(key, () => {...value.months});
      if (value.otc) _otc.add(key);
    }
  }

  /// Codes found on TPEx rather than TWSE.
  final _otc = <String>{};

  /// The codes held at the last fetch, so a new one is fetched at once.
  var _asked = <String>{};

  Set<String> get _held => {
    for (final h in _holdings.all)
      if (h.shares > 0) h.code,
  };

  void _changed() {
    final held = _held;
    final fresh = held.difference(_asked).where((c) => !_holdings.hasQuote(c));
    if (fresh.isNotEmpty && !busy) refresh(force: true).ignore();
  }

  @override
  Future<void> refresh({bool force = false}) => attempt(force: force, () async {
    final codes = _held;
    _asked = codes;
    // Closes and rates come from different places: asked side by side.
    final (quotes, rates) = await (
      _journal.refreshQuotes(codes, reshapedBy: _holdings.reshapedBy),
      _journal.refreshRates(),
    ).wait;
    if (quotes || rates) _publish();
    return marketProblem(
      missed: _journal.unquoted,
      doubted: [..._journal.doubtfulCloses, ..._journal.doubtfulRates],
    );
  });

  /// What the journal keeps of the market, given to the ledger.
  void _publish() {
    final market = _journal.market();
    _commands.setMarket(
      holdings: market.holdings,
      moves: market.moves,
      rates: market.rates,
      sellRates: market.sellRates,
      quotedOn: market.quotedOn,
      quoteDays: market.days,
      history: market.history,
    );
  }

  /// [code]'s daily closes from [from] to today, oldest first: each month
  /// from TWSE's report, or TPEx's for a stock traded over the counter.
  /// Months before this one are kept ([kept]) once read; this month is
  /// asked again (the gateway keeps it for 20 minutes). Months that
  /// cannot be read are left out. The past days among them the dated
  /// table lacks are kept in it (`keepPastCloses`, N3), so a past day's
  /// net worth has its close without waiting for daily fetches.
  ///
  /// Each month asked names [code] to the exchange (TWSE or TPEx), as
  /// their monthly reports are per stock; the day lists the prices come
  /// from are one for all.
  @override
  Future<List<(DateTime, double)>> history(String code, DateTime from) async {
    final gateway = _journal.gateway;
    if (gateway == null) return const [];
    await (_loaded ??= _load());
    final kept = _months[code] ??= {};
    final today = _today();
    final closes = <(DateTime, double)>[];
    final last = monthStart(today);
    var changed = false;
    for (final month in monthStarts(from, last)) {
      final key = YearMonth.of(month).toString();
      final current = month == last;
      var days = current ? null : kept[key];
      if (days == null) {
        days = await _fetchMonth(gateway, code, month.year, month.month);
        if (days != null && !current) {
          kept[key] = days;
          changed = true;
        }
      }
      closes.addAll(days ?? const []);
    }
    if (changed) await _write();
    if (await _journal.keepPastCloses(
      code,
      closes,
      reshapedBy: _holdings.reshapedBy,
    )) {
      _publish();
    }
    return closes;
  }

  Future<List<(DateTime, double)>?> _fetchMonth(
    MarketDataGateway gateway,
    String code,
    int year,
    int month,
  ) async {
    for (final otc in _otc.contains(code) ? [true, false] : [false, true]) {
      final result = await gateway.monthCloses(code, year, month, otc: otc);
      final value = result.value;
      if (value != null && value.isNotEmpty) {
        if (otc) _otc.add(code);
        return [
          for (final c in value)
            if (parseDecimal(c.decimalPrice) case final price?)
              (c.date.asUtcMidnight, price),
        ];
      }
      if (result.state == MarketState.failed) return null;
    }
    // Neither exchange traded it that month: an empty month, kept.
    return const [];
  }

  /// Keeps every code's finished months, sealed.
  Future<void> _write() async => kept?.write({
    for (final MapEntry(:key, :value) in _months.entries)
      key: (otc: _otc.contains(key), months: value),
  });

  @override
  void dispose() {
    _changes.removeListener(_changed);
    super.dispose();
  }
}
