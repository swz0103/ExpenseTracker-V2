part of 'vault_journal.dart';

/// Trades, dividends and splits: how the screens' investment entries
/// become the ledger's investment commands, and back.
extension _Investments on VaultJournal {
  /// The screens' trade entries and, for each instrument traded, a
  /// holding to replay them onto, priced at its last trade.
  (List<ui.Entry>, List<ui.Holding>) _investments(Map<PublicId, String> notes) {
    final entries = <ui.Entry>[];
    final quotes = <String, (String, double)>{};
    final instruments = <String, InvestmentInstrument?>{};
    for (final account in _store.investmentAccounts(_workspace)) {
      final funding = account.fundingCashAccountId.value;
      final held = <String, int>{};
      for (final r in _store.tradeRecords(account.id)) {
        final instrumentId = r['instrumentId']! as String;
        final instrument = instruments.putIfAbsent(
          instrumentId,
          () => _store.instrument(PublicId.parse(instrumentId)),
        );
        if (instrument == null) continue;
        final code = instrument.symbol;
        final id = (r['postingId'] as String?) ?? r['id']! as String;
        final note = notes[PublicId.parse(id)] ?? '';
        final date = _date(BusinessDate.parse(r['date']! as String));
        final shares = _whole(r['quantity']);
        final before = held[code] ?? 0;
        int money(String key) {
          final json = r[key];
          return json is Map<String, Object?> ? _int(Money.fromJson(json)) : 0;
        }

        switch (r['kind']) {
          case 'buy' || 'sell':
            final buy = r['kind'] == 'buy';
            held[code] = buy ? before + shares : before - shares;
            final gross = money('gross');
            final method = r['costMethod'];
            if (shares > 0) quotes[code] = (instrument.name, gross / shares);
            entries.add(
              ui.Entry(
                id: id,
                date: date,
                type: buy ? ui.EntryType.buy : ui.EntryType.sell,
                amount: gross,
                account: funding,
                category: '投資',
                note: note,
                holding: code,
                shares: shares,
                fee: money('fee'),
                tax: money('tax'),
                average: method == InvestmentCostMethod.averageCost.name,
              ),
            );
          case 'dividend':
            final withheld = money('withholdingTax');
            entries.add(
              ui.Entry(
                id: id,
                date: date,
                type: ui.EntryType.dividend,
                amount: money('net') + withheld,
                account: funding,
                category: '股息收入',
                note: note,
                holding: code,
                tax: withheld,
              ),
            );
          case 'split' || 'action':
            final after =
                before * (r['newShares']! as int) ~/ (r['oldShares']! as int);
            held[code] = after;
            entries.add(
              ui.Entry(
                id: id,
                date: date,
                type: ui.EntryType.dividend,
                amount: money('net'),
                account: funding,
                category: '股息收入',
                note: note,
                holding: code,
                shares: after - before,
                split: r['kind'] == 'split',
              ),
            );
        }
      }
    }
    return (
      entries,
      [
        for (final MapEntry(key: code, value: (name, price)) in quotes.entries)
          ui.Holding(
            code,
            name,
            shares: 0,
            price: _quotes[code] ?? price,
            cost: 0,
            change: 0,
          ),
      ],
    );
  }

  Future<void> _trade(
    PublicId id,
    ui.Entry e,
    Account funding,
    BusinessDate day,
  ) async {
    final code = e.holding;
    if (code == null || code.isEmpty) {
      throw const AppFailure(FailureKind.notFound, 'investment.not-found');
    }
    final account = await _investmentAccount(funding);
    final instrument = await _instrument(code);
    final target = TradeTarget(
      accountId: account,
      instrumentId: instrument,
      funding: VaultJournal._ref(funding),
    );
    switch (e.type) {
      case ui.EntryType.buy:
        await _invest.buy(
          BuyInvestment(
            operation: _op(),
            buyId: PublicId.generate(),
            lotId: PublicId.generate(),
            postingId: id,
            target: target,
            tradedOn: day,
            quantity: '${e.shares}',
            unitPrice: _unitPrice(e.amount, e.shares),
            gross: _ntd(e.amount),
            fee: _ntd(e.fee),
            tax: _ntd(e.tax),
          ),
        );
      case ui.EntryType.sell:
        await _invest.sell(
          SellInvestment(
            operation: _op(),
            sellId: PublicId.generate(),
            postingId: id,
            target: target,
            tradedOn: day,
            costMethod: e.average
                ? InvestmentCostMethod.averageCost
                : InvestmentCostMethod.fifo,
            quantity: '${e.shares}',
            unitPrice: _unitPrice(e.amount, e.shares),
            gross: _ntd(e.amount),
            fee: _ntd(e.fee),
            tax: _ntd(e.tax),
          ),
        );
      default:
        await _dividend(id, e, day, target);
    }
  }

  /// A dividend in cash, in shares, or a split; a stock dividend paid
  /// with cash records both.
  Future<void> _dividend(
    PublicId id,
    ui.Entry e,
    BusinessDate day,
    TradeTarget target,
  ) async {
    if (e.shares < 0) {
      final held = _held(target.accountId, target.instrumentId, day);
      await _invest.corporateAction(
        RecordCorporateAction(
          operation: _op(),
          actionId: PublicId.generate(),
          postingId: id,
          target: target,
          effectiveOn: day,
          newShares: held + e.shares,
          oldShares: held,
          capitalReturned: e.amount > 0 ? _ntd(e.amount) : null,
        ),
      );
      return;
    }
    if (e.shares > 0) {
      final held = _held(target.accountId, target.instrumentId, day);
      if (e.split) {
        await _invest.split(
          SplitInvestment(
            operation: _op(),
            splitId: PublicId.generate(),
            accountId: target.accountId,
            instrumentId: target.instrumentId,
            effectiveOn: day,
            newShares: held + e.shares,
            oldShares: held,
          ),
        );
      } else {
        await _invest.corporateAction(
          RecordCorporateAction(
            operation: _op(),
            actionId: PublicId.generate(),
            postingId: PublicId.generate(),
            target: target,
            effectiveOn: day,
            newShares: held + e.shares,
            oldShares: held,
          ),
        );
      }
    }
    if (e.amount <= 0) return;
    await _invest.dividend(
      RecordDividend(
        operation: _op(),
        dividendId: PublicId.generate(),
        postingId: id,
        target: target,
        paidOn: day,
        gross: _ntd(e.amount),
        withholdingTax: _ntd(e.tax),
        fee: _ntd(0),
        net: _ntd(e.amount - e.tax),
      ),
    );
  }

  /// Whole shares of [instrument] [account] holds now.
  int _held(PublicId account, PublicId instrument, BusinessDate day) {
    var held = 0;
    for (final lot in _store.holdings(account, instrument)) {
      if (lot.acquiredOn.compareTo(day) > 0) continue;
      held += _whole(lot.remainingQuantity.toString());
    }
    return held;
  }

  /// The investment account [funding] pays for trades, opened with a
  /// broker of its own the first time.
  Future<PublicId> _investmentAccount(Account funding) async {
    for (final a in _store.investmentAccounts(_workspace)) {
      if (a.fundingCashAccountId == funding.id) return a.id;
    }
    final broker = PublicId.generate();
    await _invest.registerBroker(
      RegisterBroker(operation: _op(), brokerId: broker, name: '券商'),
    );
    final id = PublicId.generate();
    await _invest.openAccount(
      OpenInvestmentAccount(
        operation: _op(),
        accountId: id,
        brokerId: broker,
        fundingAccountId: funding.id,
        name: '${funding.name}證券',
      ),
    );
    return id;
  }

  /// The instrument listed as [code], registered the first time.
  Future<PublicId> _instrument(String code) async {
    final symbol = code.toUpperCase();
    final etf = symbol.startsWith('00');
    final listed = _store.listedInstrument('TWSE', symbol);
    if (listed != null) return listed;
    final id = PublicId.generate();
    await _invest.registerInstrument(
      RegisterInstrument(
        operation: _op(),
        instrumentId: id,
        kind: etf ? InstrumentKind.etf : InstrumentKind.stock,
        marketCode: 'TWSE',
        symbol: symbol,
        name: symbol,
        currency: homeCurrency,
      ),
    );
    return id;
  }

  /// The investment account, instrument and trade behind the entry [id].
  (PublicId, PublicId, PublicId)? _tradeOf(String id) {
    for (final account in _store.investmentAccounts(_workspace)) {
      for (final r in _store.tradeRecords(account.id)) {
        if (r['postingId'] != id && r['id'] != id) continue;
        return (
          account.id,
          PublicId.parse(r['instrumentId']! as String),
          PublicId.parse(r['id']! as String),
        );
      }
    }
    return null;
  }
}
