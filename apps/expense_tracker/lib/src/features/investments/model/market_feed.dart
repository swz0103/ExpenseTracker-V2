import 'dart:convert';
import 'dart:io';

import 'package:market/market_data.dart';

import '../../../core/connector.dart';
import '../../../core/ledger/ledger.dart';
import '../../../core/ledger/table_journal.dart';

/// Closing prices and exchange rates for [ledger], fetched at most every
/// 20 minutes: when the ledger opens, when the app comes back, and at
/// once when a stock without a close is bought. A stock the exchanges do
/// not quote is named rather than left to look like it has a value.
final class MarketFeed extends Connector implements PriceHistory {
  MarketFeed(this._journal, this._ledger, {super.clock, this.historyDir})
    : super('收盤價與匯率', gap: const Duration(minutes: 20)) {
    _ledger.addListener(_changed);
  }

  final TableJournal _journal;
  final Ledger _ledger;

  /// Where finished months of daily closes are kept, so a holding's chart
  /// asks the exchanges only for what it has not seen; none in tests.
  final Directory? historyDir;

  /// Each code's months of closes read this run, by `yyyy-mm`.
  final _months = <String, Map<String, List<(DateTime, double)>>>{};

  /// Codes found on TPEx rather than TWSE.
  final _otc = <String>{};

  /// The codes held at the last fetch, so a new one is fetched at once.
  var _asked = <String>{};

  Set<String> get _held => {
    for (final h in _ledger.holdings)
      if (h.shares > 0) h.code,
  };

  void _changed() {
    final held = _held;
    final fresh = held.difference(_asked).where((c) => !_ledger.hasQuote(c));
    if (fresh.isNotEmpty && !busy) refresh(force: true).ignore();
  }

  @override
  Future<void> refresh({bool force = false}) => attempt(force: force, () async {
    final codes = _held;
    _asked = codes;
    final quotes = await _journal.refreshQuotes(codes);
    final rates = await _journal.refreshRates();
    if (quotes || rates) {
      final market = _journal.market();
      _ledger.setMarket(
        holdings: market.holdings,
        moves: market.moves,
        rates: market.rates,
        quotedOn: market.quotedOn,
        quoteDays: market.days,
      );
    }
    final missed = _journal.unquoted;
    if (missed.isEmpty) return null;
    return '${missed.join('、')} 抓不到收盤價';
  });

  /// [code]'s daily closes from [from] to today, oldest first: each month
  /// from TWSE's report, or TPEx's for a stock traded over the counter.
  /// Months before this one are kept in [historyDir] once read; this
  /// month is asked again (the gateway keeps it for 20 minutes). Months
  /// that cannot be read are left out.
  @override
  Future<List<(DateTime, double)>> history(String code, DateTime from) async {
    final gateway = _journal.gateway;
    if (gateway == null) return const [];
    final kept = _months[code] ??= _read(code);
    final today = _ledger.today;
    final closes = <(DateTime, double)>[];
    var month = DateTime.utc(from.year, from.month);
    final last = DateTime.utc(today.year, today.month);
    var changed = false;
    while (!month.isAfter(last)) {
      final key = '${month.year}-${'${month.month}'.padLeft(2, '0')}';
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
      month = DateTime.utc(month.year, month.month + 1);
    }
    if (changed) _write(code, kept);
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
            (
              DateTime.utc(c.date.year, c.date.month, c.date.day),
              double.parse(c.decimalPrice),
            ),
        ];
      }
      if (result.state == MarketState.failed) return null;
    }
    // Neither exchange traded it that month: an empty month, kept.
    return const [];
  }

  File? _file(String code) {
    final dir = historyDir;
    return dir == null ? null : File('${dir.path}/$code.json');
  }

  Map<String, List<(DateTime, double)>> _read(String code) {
    final file = _file(code);
    if (file == null || !file.existsSync()) return {};
    try {
      final json = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
      if (json['otc'] == true) _otc.add(code);
      final months = json['months'] as Map<String, Object?>;
      return {
        for (final MapEntry(:key, :value) in months.entries)
          key: [
            for (final row in value! as List)
              (
                DateTime.parse((row as List)[0] as String),
                (row[1] as num).toDouble(),
              ),
          ],
      };
    } on Object {
      // A cache that cannot be read is fetched again.
      return {};
    }
  }

  void _write(String code, Map<String, List<(DateTime, double)>> months) {
    final file = _file(code);
    if (file == null) return;
    try {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(
        jsonEncode({
          'otc': _otc.contains(code),
          'months': {
            for (final MapEntry(:key, :value) in months.entries)
              key: [
                for (final (day, price) in value)
                  [day.toIso8601String().substring(0, 10), price],
              ],
          },
        }),
      );
    } on Object {
      // Kept in memory for this run.
    }
  }

  @override
  void dispose() {
    _ledger.removeListener(_changed);
    super.dispose();
  }
}
