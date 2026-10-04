part of 'ledger_store.dart';

/// Investment reads for the screens: accounts, instruments, holdings,
/// trade history and income.
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

  /// The trades of [accountId], newest first, optionally for one
  /// instrument. Voided trades are left out.
  List<InvestmentTrade> tradeHistory(
    PublicId accountId, {
    PublicId? instrumentId,
  }) {
    final rows = _store.select(
      'SELECT payload FROM invest_trades WHERE account_id = ? '
      'AND (? IS NULL OR instrument_id = ?) '
      "AND json_extract(payload, '\$.id') NOT IN "
      '(SELECT trade_id FROM invest_voids) ORDER BY seq DESC',
      [accountId.value, instrumentId?.value, instrumentId?.value],
    );
    return [
      for (final row in rows)
        InvestmentRecords.readTrade(_json(row['payload'])),
    ];
  }

  /// Realized results of sells and net dividends in [workspace] dated
  /// [from] through [through], keyed by currency code.
  Map<String, InvestmentIncome> investmentIncome(
    WorkspaceId workspace, {
    required BusinessDate from,
    required BusinessDate through,
  }) {
    final realized = <String, Money>{};
    final dividends = <String, Money>{};
    void add(Map<String, Money> totals, Money amount) {
      final code = amount.currency.code;
      final earlier = totals[code];
      totals[code] = earlier == null ? amount : earlier + amount;
    }

    for (final account in investmentAccounts(workspace)) {
      for (final trade in tradeHistory(account.id)) {
        if (trade.date.compareTo(from) < 0 ||
            trade.date.compareTo(through) > 0) {
          continue;
        }
        if (trade.kind == 'sell' || trade.kind == 'action') {
          add(realized, trade.realized!);
        }
        if (trade.kind == 'dividend') add(dividends, trade.cash!);
      }
    }
    return {
      for (final code in {...realized.keys, ...dividends.keys})
        code: InvestmentIncome(
          realized: realized[code] ?? _zero(dividends[code]!),
          dividends: dividends[code] ?? _zero(realized[code]!),
        ),
    };
  }

  /// Dividends paid in [year], per account, instrument and currency, for
  /// the annual tax summary (feature audit G-13).
  List<DividendTotal> dividendSummary(WorkspaceId workspace, int year) {
    final totals = <(PublicId, PublicId, String), DividendTotal>{};
    for (final account in investmentAccounts(workspace)) {
      final rows = _store.select(
        'SELECT payload FROM invest_trades WHERE account_id = ? '
        "AND json_extract(payload, '\$.kind') = 'dividend' "
        "AND json_extract(payload, '\$.date') BETWEEN ? AND ? "
        "AND json_extract(payload, '\$.id') NOT IN "
        '(SELECT trade_id FROM invest_voids) ORDER BY seq',
        [account.id.value, '$year-01-01', '$year-12-31'],
      );
      for (final row in rows) {
        final json = _json(row['payload']);
        Money money(String key) =>
            Money.fromJson(json[key]! as Map<String, Object?>);
        final gross = money('gross');
        final paid = DividendTotal(
          accountId: account.id,
          instrumentId: PublicId.parse(json['instrumentId']! as String),
          gross: gross,
          withholdingTax: money('withholdingTax'),
          fee: money('fee'),
          healthPremium: money('healthPremium'),
          net: money('net'),
          payments: 1,
        );
        final key = (paid.accountId, paid.instrumentId, gross.currency.code);
        totals[key] = totals[key]?.plus(paid) ?? paid;
      }
    }
    return totals.values.toList();
  }
}
