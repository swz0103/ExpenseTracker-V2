part of 'ledger_store.dart';

/// Investment reads for the screens: accounts, instruments and holdings.
extension InvestmentQueries on LedgerStore {
  /// Open lots for one investment account and instrument, replayed from
  /// its trades.
  List<InvestmentHoldingLot> holdings(
    PublicId accountId,
    PublicId instrumentId,
  ) => InvestmentRecords.openLots(
    _readTrades(_store.select, accountId, instrumentId),
  );

  /// Investment accounts in [workspace], by name.
  List<InvestmentAccount> investmentAccounts(WorkspaceId workspace) {
    final rows = _store.select(
      "SELECT payload FROM invest_registry WHERE type = 'account' "
      "AND json_extract(payload, '\$.workspace') = ?",
      [workspace.toString()],
    );
    return [
      for (final row in rows)
        InvestmentRecords.readAccount(_json(row['payload'])),
    ]..sort((a, b) => a.name.compareTo(b.name));
  }

  InvestmentInstrument? instrument(PublicId id) {
    final rows = _store.select(
      'SELECT payload FROM invest_registry '
      "WHERE type = 'instrument' AND id = ?",
      [id.value],
    );
    return rows.isEmpty
        ? null
        : InvestmentRecords.readInstrument(_json(rows.single['payload']));
  }

  /// The instruments [accountId] still holds shares of.
  List<PublicId> positions(PublicId accountId) {
    final rows = _store.select(
      'SELECT DISTINCT instrument_id FROM invest_trades WHERE account_id = ? '
      'ORDER BY instrument_id',
      [accountId.value],
    );
    final held = <PublicId>[];
    for (final row in rows) {
      final instrument = PublicId.parse(row['instrument_id']! as String);
      if (holdings(accountId, instrument).isNotEmpty) held.add(instrument);
    }
    return held;
  }
}
