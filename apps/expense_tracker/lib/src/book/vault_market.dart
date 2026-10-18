part of 'vault_journal.dart';

/// Closing prices and the bank's rate board, fetched in the background;
/// trades are in vault_investments.dart.
extension MarketRefresh on VaultJournal {
  /// Fetches 臺灣銀行's board: the spot buying rate of each currency, what
  /// a foreign balance is worth in NT$. Returns whether any rate changed.
  Future<bool> refreshRates() async {
    final market = _market;
    if (market == null) return false;
    final board = (await market.bankRates()).value;
    if (board == null) return false;
    final fetched = <String, double>{};
    for (final MapEntry(key: code, value: row) in board.rates.entries) {
      final rate = row.valuation;
      if (rate != null) fetched[code] = rate.numerator / rate.denominator;
    }
    if (fetched.isEmpty || mapEquals(fetched, _rates)) return false;
    _rates
      ..clear()
      ..addAll(fetched);
    await _append(_ratesKind, {'asOf': '${board.asOf}', 'rates': fetched});
    return true;
  }

  /// Fetches the latest close of every instrument still held, for the
  /// holdings' value; a TWSE listing not found there is tried on TPEx.
  /// Returns whether any price changed.
  Future<bool> refreshQuotes() async {
    final market = _market;
    if (market == null) return false;
    final held = <String, InvestmentInstrument>{};
    for (final account in _store.investmentAccounts(_workspace)) {
      for (final id in _store.positions(account.id)) {
        final instrument = _store.instrument(id);
        if (instrument != null) held[instrument.symbol] = instrument;
      }
    }
    var changed = false;
    for (final MapEntry(key: symbol, value: instrument) in held.entries) {
      try {
        var result = await market.stockClose(instrument);
        if (result.state == MarketState.missing &&
            instrument.marketCode == 'TWSE') {
          result = await market.stockClose(
            InvestmentInstrument(
              id: instrument.id,
              kind: instrument.kind,
              marketCode: 'TPEX',
              symbol: instrument.symbol,
              name: instrument.name,
              tradingCurrency: instrument.tradingCurrency,
            ),
          );
        }
        final close = result.value;
        final price = close == null
            ? null
            : double.tryParse(close.decimalPrice);
        if (price == null || _quotes[symbol] == price) continue;
        _quotes[symbol] = price;
        changed = true;
      } on Object {
        continue;
      }
    }
    return changed;
  }
}
