import '../../../core/connector.dart';
import '../../../core/ledger/ledger.dart';
import '../../../core/ledger/table_journal.dart';

/// Closing prices and exchange rates for [ledger], fetched at most every
/// 20 minutes: when the ledger opens, when the app comes back, and at
/// once when a stock without a close is bought. A stock the exchanges do
/// not quote is named rather than left to look like it has a value.
final class MarketFeed extends Connector {
  MarketFeed(this._journal, this._ledger, {super.clock})
    : super('收盤價與匯率', gap: const Duration(minutes: 20)) {
    _ledger.addListener(_changed);
  }

  final TableJournal _journal;
  final Ledger _ledger;

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

  @override
  void dispose() {
    _ledger.removeListener(_changed);
    super.dispose();
  }
}
