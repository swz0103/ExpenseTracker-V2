part of 'bookkeeping.dart';

/// Investment records stored next to the ledger. Trades are an append-only
/// list per account and instrument; open lots are always replayed from it.
abstract interface class InvestmentTransaction
    implements BookkeepingTransaction {
  Future<BrokerIdentity?> broker(PublicId id);

  Future<void> saveBroker(BrokerIdentity broker);

  Future<InvestmentAccount?> investmentAccount(PublicId id);

  Future<void> saveInvestmentAccount(InvestmentAccount account);

  Future<InvestmentInstrument?> instrument(PublicId id);

  Future<bool> isListed(String marketCode, String symbol);

  Future<void> saveInstrument(InvestmentInstrument instrument);

  /// Trade records for one account and instrument, oldest first.
  Future<List<Map<String, Object?>>> trades(
    PublicId accountId,
    PublicId instrumentId,
  );

  Future<void> saveTrade(Map<String, Object?> trade);

  /// Leaves the trade out of [trades] from now on. Trade records stay.
  Future<void> voidTrade(PublicId tradeId);
}

/// Buy, sell and dividend commands. Each commits the trade record and its
/// cash posting together; the posting is then locked against reversal.
final class InvestmentBook<T extends InvestmentTransaction> {
  InvestmentBook(this._books);

  final Bookkeeping<T> _books;

  CommandRunner<T> get _runner => _books._runner;

  Future<CommandOutcome<int>> registerBroker(RegisterBroker command) =>
      _runner.run(command, (t) => _guard(() => _broker(t, command)));

  Future<CommandOutcome<int>> openAccount(OpenInvestmentAccount command) =>
      _runner.run(command, (t) => _guard(() => _account(t, command)));

  Future<CommandOutcome<int>> registerInstrument(RegisterInstrument command) =>
      _runner.run(command, (t) => _guard(() => _instrument(t, command)));

  Future<CommandOutcome<PublicId>> buy(BuyInvestment command) =>
      _runner.run(command, (t) => _guard(() => _buy(t, command)));

  Future<CommandOutcome<PublicId>> sell(SellInvestment command) =>
      _runner.run(command, (t) => _guard(() => _sell(t, command)));

  Future<CommandOutcome<PublicId>> dividend(RecordDividend command) =>
      _runner.run(command, (t) => _guard(() => _dividend(t, command)));

  Future<CommandOutcome<int>> split(SplitInvestment command) =>
      _runner.run(command, (t) => _guard(() => _split(t, command)));

  Future<CommandOutcome<PublicId>> corporateAction(
    RecordCorporateAction command,
  ) => _runner.run(command, (t) => _guard(() => _action(t, command)));

  Future<CommandOutcome<int>> rename(RenameInvestmentRecord command) =>
      _runner.run(command, (t) => _guard(() => _rename(t, command)));

  /// Stores the renamed record under the same id; the event repeats the
  /// registration with the new name, which replay stores the same way.
  Future<int> _rename(T t, RenameInvestmentRecord command) async {
    final workspace = command.operation.workspace;
    switch (command.type) {
      case InvestmentRecordType.broker:
        final current = await _found(t.broker(command.id), workspace);
        final broker = BrokerIdentity(
          id: current.id,
          workspace: current.workspace,
          name: command.name,
        );
        await t.saveBroker(broker);
        await _event(t, workspace, 'investment.broker-registered', {
          'broker': InvestmentRecords.broker(broker),
        });
      case InvestmentRecordType.account:
        final current = await _found(
          t.investmentAccount(command.id),
          workspace,
        );
        final account = InvestmentAccount(
          id: current.id,
          workspace: current.workspace,
          brokerId: current.brokerId,
          fundingCashAccountId: current.fundingCashAccountId,
          name: command.name,
          expectedVersion: current.expectedVersion,
        );
        await t.saveInvestmentAccount(account);
        await _event(t, workspace, 'investment.account-opened', {
          'account': InvestmentRecords.account(account),
        });
      case InvestmentRecordType.instrument:
        final current = await t.instrument(command.id);
        if (current == null) {
          throw const AppFailure(FailureKind.notFound, 'investment.not-found');
        }
        final instrument = InvestmentInstrument(
          id: current.id,
          kind: current.kind,
          marketCode: current.marketCode,
          symbol: current.symbol,
          name: command.name,
          tradingCurrency: current.tradingCurrency,
        );
        await t.saveInstrument(instrument);
        await _event(t, workspace, 'investment.listed', {
          'instrument': InvestmentRecords.instrument(instrument),
        });
    }
    return 1;
  }

  Future<CommandOutcome<PublicId>> voidTrade(VoidInvestmentTrade command) =>
      _runner.run(command, (t) => _guard(() => _void(t, command)));

  Future<PublicId> _void(T t, VoidInvestmentTrade command) async {
    final workspace = command.operation.workspace;
    final account = await _found(
      t.investmentAccount(command.accountId),
      workspace,
    );
    final trades = await t.trades(account.id, command.instrumentId);
    final index = trades.indexWhere((trade) {
      return trade['id'] == command.tradeId.value;
    });
    if (index < 0) {
      throw const AppFailure(FailureKind.notFound, 'investment.not-found');
    }
    final trade = trades[index];
    // Later sells and splits record the lots they changed, so only the
    // newest one can go; dividends never touch lots.
    final later = trades.skip(index + 1);
    if (trade['kind'] != 'dividend' &&
        later.any((other) => other['kind'] != 'dividend')) {
      throw const AppFailure(FailureKind.rejected, 'investment.trade-in-use');
    }
    final postingId = trade['postingId'] as String?;
    if (postingId != null) {
      await _books._reverseOwned(
        t,
        command.operation,
        command.reversalId,
        PublicId.parse(postingId),
      );
    }
    await t.voidTrade(command.tradeId);
    await _event(t, workspace, 'investment.voided', {
      'tradeId': command.tradeId.value,
    });
    return command.tradeId;
  }

  Future<PublicId> _action(T t, RecordCorporateAction command) async {
    final context = await _context(t, command.operation, command.target);
    final currency = context.instrument.tradingCurrency;
    await _books._requireNewPosting(t, command.postingId);
    final trades = await t.trades(context.account.id, context.instrument.id);
    _requireInOrder(trades, command.effectiveOn);
    final lots = _heldOn(
      InvestmentRecords.openLots(trades),
      command.effectiveOn,
    );
    if (lots.isEmpty) {
      throw const AppFailure(FailureKind.rejected, 'investment.no-holdings');
    }
    final preview = CorporateActionPreview.create(
      id: command.actionId,
      operation: command.operation,
      effectiveOn: command.effectiveOn,
      account: context.account,
      instrument: context.instrument,
      newShares: command.newShares,
      oldShares: command.oldShares,
      lots: lots,
      cashInLieu: command.cashInLieu,
      capitalReturned: command.capitalReturned,
    );
    final zero = Money(currency, BigInt.zero);
    final posting = preview.cash.minorUnits == BigInt.zero
        ? null
        : Posting.investmentSell(
            id: command.postingId,
            operation: command.operation,
            date: command.effectiveOn,
            account: await _cash(t, command, currency, command.effectiveOn),
            investmentSellId: preview.id,
            gross: preview.cash,
            fee: zero,
            tax: zero,
            cashCredit: preview.cash,
          );
    await _record(t, command.operation, posting, {
      'kind': 'action',
      'id': preview.id.value,
      'accountId': context.account.id.value,
      'instrumentId': context.instrument.id.value,
      'postingId': posting?.id.value,
      'date': command.effectiveOn.toString(),
      'newShares': command.newShares,
      'oldShares': command.oldShares,
      'net': preview.cash.toJson(),
      'realized': preview.realized.toJson(),
      'lots': [
        for (final change in preview.lots)
          {
            'lotId': change.before.id.value,
            'units': '${change.afterUnits}',
            'remainingCost': change.afterCost.toJson(),
          },
      ],
    });
    return preview.id;
  }

  Future<int> _split(T t, SplitInvestment command) async {
    final workspace = command.operation.workspace;
    final account = await _found(
      t.investmentAccount(command.accountId),
      workspace,
    );
    final instrument = await t.instrument(command.instrumentId);
    if (instrument == null) {
      throw const AppFailure(FailureKind.notFound, 'investment.not-found');
    }
    final trades = await t.trades(account.id, instrument.id);
    _requireInOrder(trades, command.effectiveOn);
    final lots = _heldOn(
      InvestmentRecords.openLots(trades),
      command.effectiveOn,
    );
    final preview = StockSplitPreview.create(
      id: command.splitId,
      operation: command.operation,
      effectiveOn: command.effectiveOn,
      broker: await _found(t.broker(account.brokerId), workspace),
      account: account,
      instrument: instrument,
      newShares: command.newShares,
      oldShares: command.oldShares,
      lots: lots,
    );
    final record = <String, Object?>{
      'version': InvestmentRecords.version,
      'kind': 'split',
      'id': preview.id.value,
      'accountId': account.id.value,
      'instrumentId': instrument.id.value,
      'postingId': null,
      'date': command.effectiveOn.toString(),
      'newShares': command.newShares,
      'oldShares': command.oldShares,
      'lots': [
        for (final change in preview.lots)
          {
            'lotId': change.before.id.value,
            'quantity': change.afterQuantity.toString(),
          },
      ],
    };
    await t.saveTrade(record);
    await _event(t, workspace, 'investment.traded', record);
    return preview.lots.length;
  }

  Future<int> _broker(T t, RegisterBroker command) async {
    if (await t.broker(command.brokerId) != null) {
      throw const AppFailure(FailureKind.conflict, 'investment.exists');
    }
    final broker = BrokerIdentity(
      id: command.brokerId,
      workspace: command.operation.workspace,
      name: command.name,
    );
    await t.saveBroker(broker);
    await _event(t, broker.workspace, 'investment.broker-registered', {
      'broker': InvestmentRecords.broker(broker),
    });
    return 1;
  }

  Future<int> _account(T t, OpenInvestmentAccount command) async {
    final workspace = command.operation.workspace;
    if (await t.investmentAccount(command.accountId) != null) {
      throw const AppFailure(FailureKind.conflict, 'investment.exists');
    }
    final broker = await _found(t.broker(command.brokerId), workspace);
    final funding = await _books._account(t, command.fundingAccountId);
    if (funding.workspace != workspace ||
        !const {AccountKind.bank, AccountKind.cash}.contains(funding.kind) ||
        funding.state != AccountState.active) {
      throw const AppFailure(FailureKind.rejected, 'investment.funding');
    }
    final account = InvestmentAccount(
      id: command.accountId,
      workspace: workspace,
      brokerId: broker.id,
      fundingCashAccountId: funding.id,
      name: command.name,
      expectedVersion: 1,
    );
    await t.saveInvestmentAccount(account);
    await _event(t, workspace, 'investment.account-opened', {
      'account': InvestmentRecords.account(account),
    });
    return 1;
  }

  Future<int> _instrument(T t, RegisterInstrument command) async {
    if (await t.instrument(command.instrumentId) != null ||
        await t.isListed(command.marketCode, command.symbol)) {
      throw const AppFailure(FailureKind.conflict, 'investment.exists');
    }
    final instrument = InvestmentInstrument(
      id: command.instrumentId,
      kind: command.kind,
      marketCode: command.marketCode,
      symbol: command.symbol,
      name: command.name,
      tradingCurrency: command.currency,
    );
    await t.saveInstrument(instrument);
    await _event(t, command.operation.workspace, 'investment.listed', {
      'instrument': InvestmentRecords.instrument(instrument),
    });
    return 1;
  }

  Future<PublicId> _buy(T t, BuyInvestment command) async {
    final context = await _context(
      t,
      command.operation,
      command.target,
      settled: command.settledAmount,
    );
    final currency = context.instrument.tradingCurrency;
    await _books._requireNewPosting(t, command.postingId);
    _requireInOrder(
      await t.trades(context.account.id, context.instrument.id),
      command.tradedOn,
    );
    final preview = InvestmentBuyPreview.create(
      id: command.buyId,
      lotId: command.lotId,
      operation: command.operation,
      tradedOn: command.tradedOn,
      broker: context.broker,
      account: context.account,
      instrument: context.instrument,
      funding: context.funding,
      quantity: ShareQuantity.parse(command.quantity),
      unitPrice: ShareUnitPrice.parse(currency, command.unitPrice),
      executedGross: command.gross,
      fee: command.fee,
      tax: command.tax,
    );
    final settles = _settlement(command.tradedOn, command.settlesOn);
    final posting = Posting.investmentBuy(
      id: command.postingId,
      operation: command.operation,
      date: settles,
      account: await _cash(t, command, currency, settles),
      investmentBuyId: preview.id,
      gross: preview.gross,
      fee: preview.fee,
      tax: preview.tax,
      cashDebit: preview.cashDebit,
      settled: command.settledAmount,
    );
    final lot = preview.lot;
    await _record(t, command.operation, posting, {
      'kind': 'buy',
      'id': preview.id.value,
      'accountId': lot.investmentAccountId.value,
      'instrumentId': lot.instrumentId.value,
      'postingId': posting.id.value,
      'date': lot.acquiredOn.toString(),
      'lotId': lot.id.value,
      'quantity': lot.quantity.toString(),
      'unitPrice': lot.unitPrice.toString(),
      'gross': lot.gross.toJson(),
      'fee': lot.fee.toJson(),
      'tax': lot.tax.toJson(),
      'cost': lot.acquisitionCashCost.toJson(),
    });
    return posting.id;
  }

  Future<PublicId> _sell(T t, SellInvestment command) async {
    final context = await _context(
      t,
      command.operation,
      command.target,
      settled: command.settledAmount,
    );
    final currency = context.instrument.tradingCurrency;
    await _books._requireNewPosting(t, command.postingId);
    final trades = await t.trades(context.account.id, context.instrument.id);
    _requireInOrder(trades, command.tradedOn);
    final lots = _heldOn(InvestmentRecords.openLots(trades), command.tradedOn);
    if (lots.isEmpty) {
      throw const AppFailure(FailureKind.rejected, 'investment.no-holdings');
    }
    // One holding keeps one cost method, or its basis stops adding up
    // (health check G2-25).
    for (final trade in trades) {
      if (trade['kind'] == 'sell' &&
          trade['costMethod'] != command.costMethod.name) {
        throw const AppFailure(FailureKind.rejected, 'investment.cost-method');
      }
    }
    final preview = InvestmentSellPreview.create(
      id: command.sellId,
      operation: command.operation,
      tradedOn: command.tradedOn,
      broker: context.broker,
      account: context.account,
      instrument: context.instrument,
      funding: context.funding,
      costMethod: command.costMethod,
      quantity: ShareQuantity.parse(command.quantity),
      unitPrice: ShareUnitPrice.parse(currency, command.unitPrice),
      executedGross: command.gross,
      fee: command.fee,
      tax: command.tax,
      lots: lots,
    );
    final settles = _settlement(command.tradedOn, command.settlesOn);
    final account = await _cash(t, command, currency, settles);
    // A sale whose fees take exactly all of it moves no cash (G1-06).
    final posting = preview.netCashCredit.minorUnits == BigInt.zero
        ? null
        : Posting.investmentSell(
            id: command.postingId,
            operation: command.operation,
            date: settles,
            account: account,
            investmentSellId: preview.id,
            gross: preview.gross,
            fee: preview.fee,
            tax: preview.tax,
            cashCredit: preview.netCashCredit,
            settled: command.settledAmount,
          );
    await _record(t, command.operation, posting, {
      'kind': 'sell',
      'id': preview.id.value,
      'accountId': context.account.id.value,
      'instrumentId': context.instrument.id.value,
      'postingId': posting?.id.value,
      'date': command.tradedOn.toString(),
      'costMethod': preview.costMethod.name,
      'quantity': preview.quantity.toString(),
      'unitPrice': preview.unitPrice.toString(),
      'gross': preview.gross.toJson(),
      'fee': preview.fee.toJson(),
      'tax': preview.tax.toJson(),
      'net': preview.netCashCredit.toJson(),
      'allocatedCost': preview.allocatedCost.toJson(),
      'realized': preview.realizedResult.toJson(),
      'lots': [
        for (final allocation in preview.allocations)
          {
            'lotId': allocation.lot.id.value,
            'soldUnits': '${allocation.soldQuantityUnits}',
            'remainingUnits': '${allocation.remainingQuantityUnits}',
            'remainingCost': allocation.remainingCost.toJson(),
          },
      ],
    });
    return posting?.id ?? preview.id;
  }

  Future<PublicId> _dividend(T t, RecordDividend command) async {
    final context = await _context(
      t,
      command.operation,
      command.target,
      settled: command.settledAmount,
    );
    await _books._requireNewPosting(t, command.postingId);
    final exDate = command.exDividendOn;
    if (exDate != null && exDate.compareTo(command.paidOn) > 0) {
      throw const AppFailure(FailureKind.rejected, 'investment.ex-date');
    }
    final premium =
        command.healthPremium ?? Money(command.fee.currency, BigInt.zero);
    if (premium.currency != command.fee.currency ||
        premium.minorUnits.isNegative) {
      throw const AppFailure(FailureKind.rejected, 'investment.premium');
    }
    final preview = InvestmentDividendPreview.create(
      id: command.dividendId,
      operation: command.operation,
      paidOn: command.paidOn,
      broker: context.broker,
      account: context.account,
      instrument: context.instrument,
      funding: context.funding,
      gross: command.gross,
      withholdingTax: command.withholdingTax,
      fee: command.fee + premium,
      reportedNet: command.net,
    );
    final currency = context.instrument.tradingCurrency;
    final account = await _cash(t, command, currency, command.paidOn);
    // Everything withheld: nothing is paid out (G1-06).
    final posting = preview.netCashCredit.minorUnits == BigInt.zero
        ? null
        : Posting.investmentDividend(
            id: command.postingId,
            operation: command.operation,
            date: command.paidOn,
            account: account,
            investmentDividendId: preview.id,
            gross: preview.gross,
            withholdingTax: preview.withholdingTax,
            fee: preview.fee,
            cashCredit: preview.netCashCredit,
            settled: command.settledAmount,
          );
    await _record(t, command.operation, posting, {
      'kind': 'dividend',
      'id': preview.id.value,
      'accountId': context.account.id.value,
      'instrumentId': context.instrument.id.value,
      'postingId': posting?.id.value,
      'date': command.paidOn.toString(),
      'gross': preview.gross.toJson(),
      'withholdingTax': preview.withholdingTax.toJson(),
      'fee': command.fee.toJson(),
      'healthPremium': premium.toJson(),
      'exDate': exDate?.toString(),
      'net': preview.netCashCredit.toJson(),
    });
    return posting?.id ?? preview.id;
  }

  BusinessDate _settlement(BusinessDate tradedOn, BusinessDate? settlesOn) {
    if (settlesOn == null) return tradedOn;
    if (settlesOn.compareTo(tradedOn) < 0) {
      throw const AppFailure(FailureKind.rejected, 'investment.settlement');
    }
    return settlesOn;
  }

  /// Sells and splits record the lots they changed, so nothing may be
  /// booked before the latest of them; void the later ones first
  /// (health check G2-05).
  void _requireInOrder(List<Map<String, Object?>> trades, BusinessDate date) {
    for (final trade in trades) {
      if (const {'sell', 'split', 'action'}.contains(trade['kind']) &&
          BusinessDate.parse(trade['date']! as String).compareTo(date) > 0) {
        throw const AppFailure(FailureKind.rejected, 'investment.backdated');
      }
    }
  }

  /// Only lots bought by [date] can be sold or split on it.
  List<InvestmentHoldingLot> _heldOn(
    List<InvestmentHoldingLot> lots,
    BusinessDate date,
  ) => [
    for (final lot in lots)
      if (lot.acquiredOn.compareTo(date) <= 0) lot,
  ];

  Future<_TradeContext> _context(
    T t,
    OperationKey operation,
    TradeTarget target, {
    Money? settled,
  }) async {
    final workspace = operation.workspace;
    final account = await _found(
      t.investmentAccount(target.accountId),
      workspace,
    );
    final instrument = await t.instrument(target.instrumentId);
    if (instrument == null) {
      throw const AppFailure(FailureKind.notFound, 'investment.not-found');
    }
    if (target.funding.id != account.fundingCashAccountId) {
      throw const AppFailure(FailureKind.rejected, 'investment.funding');
    }
    final cash = await _books._account(t, target.funding.id);
    // Settled in another currency, the broker converts: the trade itself is
    // still in the instrument's currency (feature audit G-06).
    if (settled != null &&
        (settled.currency != cash.currency ||
            cash.currency.code == instrument.tradingCurrency.code)) {
      throw const AppFailure(FailureKind.rejected, 'investment.settlement');
    }
    return _TradeContext(
      broker: await _found(t.broker(account.brokerId), workspace),
      account: account,
      instrument: instrument,
      funding: FundingCashAccount(
        id: cash.id,
        workspace: cash.workspace,
        currency: settled == null ? cash.currency : instrument.tradingCurrency,
        expectedVersion: target.funding.expectedVersion,
      ),
    );
  }

  /// The settlement account, checked at the version the person saw.
  Future<PostingAccount> _cash(
    T t,
    Command<PublicId> command,
    Currency currency,
    BusinessDate date,
  ) {
    final (target, settled) = switch (command) {
      BuyInvestment trade => (trade.target, trade.settledAmount),
      SellInvestment trade => (trade.target, trade.settledAmount),
      RecordDividend trade => (trade.target, trade.settledAmount),
      RecordCorporateAction trade => (trade.target, null),
      _ => throw StateError('Not a trade.'),
    };
    return _books._postable(
      t,
      target.funding,
      command.operation.workspace,
      settled?.currency ?? currency,
      date,
    );
  }

  Future<void> _record(
    T t,
    OperationKey operation,
    Posting? posting,
    Map<String, Object?> trade,
  ) async {
    final record = {'version': InvestmentRecords.version, ...trade};
    // The posting first: the trade row refers to it.
    if (posting != null) {
      await _books._savePosting(t, posting, PostingMetadata.none);
    }
    await t.saveTrade(record);
    await _event(t, operation.workspace, 'investment.traded', record);
  }

  Future<void> _event(
    T t,
    WorkspaceId workspace,
    String kind,
    Map<String, Object?> payload,
  ) => t.appendEvent(
    id: PublicId.generate(),
    workspace: workspace,
    kind: kind,
    payload: jsonEncode(payload),
  );
}

final class _TradeContext {
  const _TradeContext({
    required this.broker,
    required this.account,
    required this.instrument,
    required this.funding,
  });

  final BrokerIdentity broker;
  final InvestmentAccount account;
  final InvestmentInstrument instrument;
  final FundingCashAccount funding;
}

/// Looks up a workspace-owned record or fails with `investment.not-found`.
Future<R> _found<R extends Object>(
  Future<R?> lookup,
  WorkspaceId workspace,
) async {
  final value = await lookup;
  final owner = switch (value) {
    BrokerIdentity(workspace: final owner) => owner,
    InvestmentAccount(workspace: final owner) => owner,
    _ => null,
  };
  if (value == null || owner != workspace) {
    throw const AppFailure(FailureKind.notFound, 'investment.not-found');
  }
  return value;
}

/// Versioned JSON for investment registrations and trade records.
abstract final class InvestmentRecords {
  static const version = 1;

  static Map<String, Object?> broker(BrokerIdentity broker) => {
    'id': broker.id.value,
    'workspace': broker.workspace.toString(),
    'name': broker.name,
  };

  static BrokerIdentity readBroker(Map<String, Object?> json) => decoding(() {
    checkKeys(json, const {'id', 'workspace', 'name'});
    return BrokerIdentity(
      id: PublicId.parse(json['id'] as String),
      workspace: WorkspaceId.parse(json['workspace'] as String),
      name: json['name'] as String,
    );
  });

  static Map<String, Object?> account(InvestmentAccount account) => {
    'id': account.id.value,
    'workspace': account.workspace.toString(),
    'brokerId': account.brokerId.value,
    'fundingAccountId': account.fundingCashAccountId.value,
    'name': account.name,
    'accountVersion': account.expectedVersion,
  };

  static InvestmentAccount readAccount(Map<String, Object?> json) =>
      decoding(() {
        checkKeys(json, const {
          'id',
          'workspace',
          'brokerId',
          'fundingAccountId',
          'name',
          'accountVersion',
        });
        return InvestmentAccount(
          id: PublicId.parse(json['id'] as String),
          workspace: WorkspaceId.parse(json['workspace'] as String),
          brokerId: PublicId.parse(json['brokerId'] as String),
          fundingCashAccountId: PublicId.parse(
            json['fundingAccountId'] as String,
          ),
          name: json['name'] as String,
          expectedVersion: json['accountVersion'] as int,
        );
      });

  static Map<String, Object?> instrument(InvestmentInstrument instrument) => {
    'id': instrument.id.value,
    'kind': instrument.kind.name,
    'marketCode': instrument.marketCode,
    'symbol': instrument.symbol,
    'name': instrument.name,
    'currency': instrument.tradingCurrency.code,
    'scale': instrument.tradingCurrency.scale,
  };

  static InvestmentInstrument readInstrument(Map<String, Object?> json) =>
      decoding(() {
        checkKeys(json, const {
          'id',
          'kind',
          'marketCode',
          'symbol',
          'name',
          'currency',
          'scale',
        });
        return InvestmentInstrument(
          id: PublicId.parse(json['id'] as String),
          kind: InstrumentKind.values.byName(json['kind'] as String),
          marketCode: json['marketCode'] as String,
          symbol: json['symbol'] as String,
          name: json['name'] as String,
          tradingCurrency: Currency(
            json['currency'] as String,
            json['scale'] as int,
          ),
        );
      });

  /// The history view of a stored trade record.
  static InvestmentTrade readTrade(Map<String, Object?> json) => decoding(() {
    if (json['version'] != version) throw const CodecException('version');
    Money? money(String key) {
      final value = json[key] as Map<String, Object?>?;
      return value == null ? null : Money.fromJson(value);
    }

    final kind = json['kind']! as String;
    final posting = json['postingId'] as String?;
    final quantity = json['quantity'] as String?;
    final cost = money('cost');
    return InvestmentTrade(
      id: PublicId.parse(json['id']! as String),
      kind: switch (kind) {
        'buy' || 'sell' || 'split' || 'dividend' || 'action' => kind,
        _ => throw const CodecException('trade'),
      },
      accountId: PublicId.parse(json['accountId']! as String),
      instrumentId: PublicId.parse(json['instrumentId']! as String),
      date: BusinessDate.parse(json['date']! as String),
      postingId: posting == null ? null : PublicId.parse(posting),
      quantity: quantity == null ? null : ShareQuantity.parse(quantity),
      gross: money('gross'),
      cash: cost == null ? money('net') : -cost,
      realized: money('realized'),
    );
  });

  /// Replays buys and sells into the open lots, oldest first. Every sell
  /// rewrites the lots it lists, so a lot's version counts its changes.
  static List<InvestmentHoldingLot> openLots(
    List<Map<String, Object?>> trades,
  ) => decoding(() {
    final lots = <String, _LotState>{};
    for (final trade in trades) {
      if (trade['version'] != version) throw const CodecException('version');
      final accountId = PublicId.parse(trade['accountId'] as String);
      final instrumentId = PublicId.parse(trade['instrumentId'] as String);
      switch (trade['kind']) {
        case 'buy':
          final cost = Money.fromJson(trade['cost'] as Map<String, Object?>);
          final quantity = ShareQuantity.parse(trade['quantity'] as String);
          final scale = BigInt.from(10).pow(12 - quantity.scale);
          lots[trade['lotId'] as String] = _LotState(
            accountId: accountId,
            instrumentId: instrumentId,
            acquiredOn: BusinessDate.parse(trade['date'] as String),
            units: quantity.coefficient * scale,
            cost: cost,
            version: 1,
          );
        case 'sell':
          for (final change in trade['lots'] as List) {
            final entry = change as Map<String, Object?>;
            final id = entry['lotId'] as String;
            final lot = lots[id] ?? (throw const CodecException('lot'));
            final units = BigInt.parse(entry['remainingUnits'] as String);
            if (units == BigInt.zero) {
              lots.remove(id);
              continue;
            }
            lots[id] = _LotState(
              accountId: lot.accountId,
              instrumentId: lot.instrumentId,
              acquiredOn: lot.acquiredOn,
              units: units,
              cost: Money.fromJson(
                entry['remainingCost'] as Map<String, Object?>,
              ),
              version: lot.version + 1,
            );
          }
        case 'split':
          for (final change in trade['lots']! as List) {
            final entry = change as Map<String, Object?>;
            final id = entry['lotId']! as String;
            final lot = lots[id] ?? (throw const CodecException('lot'));
            final quantity = ShareQuantity.parse(entry['quantity']! as String);
            final scale = BigInt.from(10).pow(12 - quantity.scale);
            lots[id] = _LotState(
              accountId: lot.accountId,
              instrumentId: lot.instrumentId,
              acquiredOn: lot.acquiredOn,
              units: quantity.coefficient * scale,
              cost: lot.cost,
              version: lot.version + 1,
            );
          }
        case 'action':
          for (final change in trade['lots']! as List) {
            final entry = change as Map<String, Object?>;
            final id = entry['lotId']! as String;
            final lot = lots[id] ?? (throw const CodecException('lot'));
            final units = BigInt.parse(entry['units']! as String);
            if (units == BigInt.zero) {
              lots.remove(id);
              continue;
            }
            lots[id] = _LotState(
              accountId: lot.accountId,
              instrumentId: lot.instrumentId,
              acquiredOn: lot.acquiredOn,
              units: units,
              cost: Money.fromJson(
                entry['remainingCost']! as Map<String, Object?>,
              ),
              version: lot.version + 1,
            );
          }
        case 'dividend':
          break;
        default:
          throw const CodecException('trade');
      }
    }
    return [
      for (final MapEntry(:key, :value) in lots.entries)
        InvestmentHoldingLot(
          id: PublicId.parse(key),
          investmentAccountId: value.accountId,
          instrumentId: value.instrumentId,
          acquiredOn: value.acquiredOn,
          remainingQuantity: ShareQuantity.parse(_decimal(value.units)),
          remainingCost: value.cost,
          expectedVersion: value.version,
        ),
    ];
  });
}

/// One recorded trade, as the trade history screen lists it.
final class InvestmentTrade {
  const InvestmentTrade({
    required this.id,
    required this.kind,
    required this.accountId,
    required this.instrumentId,
    required this.date,
    this.postingId,
    this.quantity,
    this.gross,
    this.cash,
    this.realized,
  });

  final PublicId id;

  /// `buy`, `sell`, `split`, `dividend` or `action` (a corporate action).
  final String kind;
  final PublicId accountId;
  final PublicId instrumentId;
  final BusinessDate date;

  /// The cash posting; a split has none.
  final PublicId? postingId;

  /// Shares bought or sold.
  final ShareQuantity? quantity;

  /// Price times quantity, or the dividend before tax and fees.
  final Money? gross;

  /// The change in cash: negative for a buy, the net received for a sell
  /// or a dividend.
  final Money? cash;

  /// Proceeds less the cost of the shares sold, for a sell.
  final Money? realized;
}

final class _LotState {
  const _LotState({
    required this.accountId,
    required this.instrumentId,
    required this.acquiredOn,
    required this.units,
    required this.cost,
    required this.version,
  });

  final PublicId accountId;
  final PublicId instrumentId;
  final BusinessDate acquiredOn;

  /// Quantity in units of 10^-12 shares.
  final BigInt units;
  final Money cost;
  final int version;
}

/// 10^-12 share units as canonical decimal text, for example `1.5`.
String _decimal(BigInt units) {
  final digits = units.toString().padLeft(13, '0');
  final whole = digits.substring(0, digits.length - 12);
  final fraction = digits
      .substring(digits.length - 12)
      .replaceAll(RegExp(r'0+$'), '');
  return fraction.isEmpty ? whole : '$whole.$fraction';
}
