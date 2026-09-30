part of 'investment_adapter.dart';

/// The schema-22 disposition and the matching cash event. This is never a
/// standalone cash receipt: the persisted allocations own the lot change.
final class InvestmentSellFact {
  const InvestmentSellFact(this.preview, this.eventId, this.sequence);
  final InvestmentSellPreview preview;
  final PublicId eventId;
  final int sequence;
}

/// Replays immutable buy and sale facts to obtain current open lots. Each sale
/// is recalculated against the preceding state; a missing or changed fact
/// fails closed before a new preview can be accepted.
Future<List<InvestmentHoldingLot>> investmentHoldingLots(
  ProbeDatabase db,
  WorkspaceId workspace,
  PublicId investmentAccountId,
  PublicId instrumentId,
) async {
  _requireSaleSchema(db);
  final position = await _loadPosition(
    db,
    workspace,
    investmentAccountId,
    instrumentId,
  );
  return List.unmodifiable(position.lots.values.toList()..sort(_lotOrder));
}

/// One transaction covers the cash credit, disposition, all lot allocations,
/// operation receipt and audit. A retry retains the same event and operation.
Future<CommitResult> commitInvestmentSell(
  ProbeDatabase db,
  InvestmentSellPreview preview,
  Posting posting, {
  void Function(String)? checkpoint,
}) => db.transaction(() async {
  _requireSaleSchema(db);
  _requireSellPosting(preview, posting);
  final payload = jsonEncode(_sellMap(preview));
  final receipt = jsonEncode(['investment-sell-v1', posting.id.value, payload]);
  final result = await OperationWriter(db).commit(
    preview.operation,
    receipt,
    posting.id,
    () async {
      final funding = await AccountsAdapter(db)
          .read(preview.operation.workspace, preview.funding.id);
      if (funding.kind != AccountKind.cash &&
          funding.kind != AccountKind.bank) {
        throw const FormatException(
          'Investment settlement must use cash or bank',
        );
      }
      funding.requirePosting(
        workspace: preview.operation.workspace,
        currency: preview.cashCredit.currency,
        expectedVersion: preview.funding.expectedVersion,
        date: preview.tradedOn,
      );
      final position = await _loadPosition(
        db,
        preview.operation.workspace,
        preview.account.id,
        preview.instrument.id,
      );
      if (position.identity == null ||
          !_matchesIdentity(preview, position.identity!)) {
        throw const FormatException('Investment position identity mismatch');
      }
      preview.verifyCurrentLots(position.lots.values.toList());
      if (position.lastMethod != null &&
          position.lastMethod != preview.costMethod) {
        throw const FormatException(
          'Investment cost method is fixed per position',
        );
      }
      if (position.lastDate != null &&
          position.lastDate!.compareTo(preview.tradedOn) > 0) {
        throw const FormatException('Investment sale date precedes prior sale');
      }
      if (position.lastSplitDate != null &&
          position.lastSplitDate!.compareTo(preview.tradedOn) > 0) {
        throw const FormatException('Investment sale date precedes split');
      }
      await LedgerAdapter(
        db,
        sourceContext: 'investment-sell-v1',
      ).insert(posting, checkpoint: checkpoint);
      checkpoint?.call('investmentSellEvent');
      final ws = preview.operation.workspace.toString();
      final sequence = position.saleCount + 1;
      await db.customStatement(
        'INSERT INTO investment_sales VALUES (?,?,?,?,?,?,?,?,?,?,?)',
        [
          ws,
          preview.id.value,
          preview.operation.operation.toString(),
          posting.id.value,
          preview.account.id.value,
          preview.instrument.id.value,
          preview.broker.id.value,
          preview.funding.id.value,
          sequence,
          preview.costMethod.name,
          payload,
        ],
      );
      checkpoint?.call('investmentSell');
      for (var index = 0; index < preview.allocations.length; index++) {
        final allocation = preview.allocations[index];
        await db.customStatement(
          'INSERT INTO investment_sale_allocations VALUES (?,?,?,?,?,?,?,?,?)',
          [
            ws,
            preview.id.value,
            allocation.lot.id.value,
            index,
            allocation.soldQuantityUnits.toString(),
            allocation.allocatedSaleCost.minorUnits.toInt(),
            allocation.remainingQuantityUnits.toString(),
            allocation.remainingCost.minorUnits.toInt(),
            allocation.lot.expectedVersion,
          ],
        );
        checkpoint?.call('investmentSellAllocation');
      }
      await LedgerAdapter(db).balance(posting.legs.single.account);
    },
    'ledger.investmentSell',
    checkpoint,
  );
  if (result.id != posting.id) throw OperationConflict();
  final position = await _loadPosition(
    db,
    preview.operation.workspace,
    preview.account.id,
    preview.instrument.id,
  );
  if (position.saleCount < 1 ||
      !position.sales.any(
        (fact) =>
            fact.preview.id == preview.id &&
            fact.eventId == posting.id &&
            jsonEncode(_sellMap(fact.preview)) == payload,
      )) {
    throw OperationConflict();
  }
  return result;
});

Future<List<InvestmentSellFact>> investmentSales(
  ProbeDatabase db,
  WorkspaceId workspace,
  PublicId investmentAccountId,
  PublicId instrumentId,
) async {
  _requireSaleSchema(db);
  final position = await _loadPosition(
    db,
    workspace,
    investmentAccountId,
    instrumentId,
  );
  return List.unmodifiable(position.sales);
}

/// Full schema-22 authority check for future backup capture and restore.
/// Position reads alone cannot detect an orphan event or an unrelated sale.
Future<void> validateInvestmentSaleFacts(ProbeDatabase db) async {
  _requireSaleSchema(db);
  await validateInvestmentFacts(db);
  final positions = await db
      .customSelect(
        'SELECT DISTINCT workspace,investment_account_id,instrument_id '
        'FROM investment_sales',
      )
      .get();
  for (final row in positions) {
    await _loadPosition(
      db,
      WorkspaceId.parse(row.read<String>('workspace')),
      PublicId.parse(row.read<String>('investment_account_id')),
      PublicId.parse(row.read<String>('instrument_id')),
    );
  }
  final orphanEvents = await db
      .customSelect(
        "SELECT e.id FROM events e LEFT JOIN investment_sales s "
        "ON s.workspace=e.workspace AND s.event_id=e.id "
        "WHERE e.kind='investmentSell' AND s.sell_id IS NULL LIMIT 1",
      )
      .get();
  final orphanAllocations = await db
      .customSelect(
        'SELECT a.sell_id FROM investment_sale_allocations a '
        'LEFT JOIN investment_sales s '
        'ON s.workspace=a.workspace AND s.sell_id=a.sell_id '
        'WHERE s.sell_id IS NULL LIMIT 1',
      )
      .get();
  final orphanAudits = await db
      .customSelect(
        "SELECT a.operation_id FROM audit a LEFT JOIN investment_sales s "
        "ON s.workspace=a.workspace AND s.operation_id=a.operation_id "
        "WHERE a.kind='ledger.investmentSell' AND s.sell_id IS NULL LIMIT 1",
      )
      .get();
  if (orphanEvents.isNotEmpty ||
      orphanAllocations.isNotEmpty ||
      orphanAudits.isNotEmpty) {
    throw const FormatException('Orphan investment sale fact');
  }
}

void _requireSaleSchema(ProbeDatabase db) {
  if (!db.investmentSalesAware) {
    throw const FormatException('Investment sale schema unavailable');
  }
}

void _requireSellPosting(InvestmentSellPreview preview, Posting posting) {
  final leg = posting.legs.singleOrNull;
  final cash = posting.investmentSell;
  if (posting.kind != PostingKind.investmentSell ||
      posting.operation != preview.operation ||
      posting.date != preview.tradedOn ||
      cash == null ||
      cash.sellId != preview.id ||
      cash.gross != preview.gross ||
      cash.fee != preview.fee ||
      cash.tax != preview.tax ||
      cash.cashCredit != preview.cashCredit ||
      leg == null ||
      leg.account.id != preview.funding.id ||
      leg.account.workspace != preview.funding.workspace ||
      leg.account.expectedVersion != preview.funding.expectedVersion ||
      leg.account.currency != preview.funding.currency ||
      leg.amount != preview.cashCredit ||
      leg.role != LegRole.principal ||
      posting.reportIncome.minorUnits != BigInt.zero ||
      posting.reportExpense.minorUnits != BigInt.zero ||
      posting.allocations.isNotEmpty) {
    throw const FormatException('Investment sale posting mismatch');
  }
}

Map<String, Object> _sellMap(InvestmentSellPreview preview) => {
  'version': 1,
  'workspace': preview.operation.workspace.toString(),
  'operation': preview.operation.operation.toString(),
  'sellId': preview.id.value,
  'tradedOn': preview.tradedOn.toString(),
  'brokerId': preview.broker.id.value,
  'accountId': preview.account.id.value,
  'accountVersion': preview.account.expectedVersion,
  'instrumentId': preview.instrument.id.value,
  'fundingId': preview.funding.id.value,
  'fundingVersion': preview.funding.expectedVersion,
  'costMethod': preview.costMethod.name,
  'quantity': preview.quantity.toString(),
  'unitPrice': preview.unitPrice.toString(),
  'gross': preview.gross.minorUnits.toString(),
  'fee': preview.fee.minorUnits.toString(),
  'tax': preview.tax.minorUnits.toString(),
  'cashCredit': preview.cashCredit.minorUnits.toString(),
  'allocatedCost': preview.allocatedCost.minorUnits.toString(),
  'realizedResult': preview.realizedResult.minorUnits.toString(),
  'lots': [
    for (final item in preview.allocations)
      {
        'id': item.lot.id.value,
        'acquiredOn': item.lot.acquiredOn.toString(),
        'remainingQuantity': item.lot.remainingQuantity.toString(),
        'remainingCost': item.lot.remainingCost.minorUnits.toString(),
        'expectedVersion': item.lot.expectedVersion,
      },
  ],
};

bool _matchesIdentity(InvestmentSellPreview sale, InvestmentBuyPreview buy) =>
    sale.broker.id == buy.broker.id &&
    sale.account.id == buy.account.id &&
    sale.instrument.id == buy.instrument.id &&
    sale.funding.id == buy.funding.id;

int _lotOrder(InvestmentHoldingLot a, InvestmentHoldingLot b) {
  final date = a.acquiredOn.compareTo(b.acquiredOn);
  return date == 0 ? a.id.value.compareTo(b.id.value) : date;
}

final class _InvestmentPosition {
  _InvestmentPosition(
    this.identity,
    this.lots,
    this.sales,
    this.splits,
    this.lastMethod,
    this.lastDate,
    this.lastSplitDate,
  );
  final InvestmentBuyPreview? identity;
  final Map<PublicId, InvestmentHoldingLot> lots;
  final List<InvestmentSellFact> sales;
  final List<InvestmentSplitFact> splits;
  final InvestmentCostMethod? lastMethod;
  final BusinessDate? lastDate;
  final BusinessDate? lastSplitDate;
  int get saleCount => sales.length;
  int get splitCount => splits.length;
}

Future<_InvestmentPosition> _loadPosition(
  ProbeDatabase db,
  WorkspaceId workspace,
  PublicId investmentAccountId,
  PublicId instrumentId,
) async {
  final purchases =
      (await investmentBuys(
          db,
          workspace,
          investmentAccountId,
        )).where((buy) => buy.preview.instrument.id == instrumentId).toList()
        ..sort((a, b) {
          final date = a.preview.tradedOn.compareTo(b.preview.tradedOn);
          return date == 0
              ? a.preview.lot.id.value.compareTo(b.preview.lot.id.value)
              : date;
        });
  final identity = purchases.firstOrNull?.preview;
  for (final buy in purchases) {
    if (identity == null ||
        buy.preview.account.id != identity.account.id ||
        buy.preview.instrument.id != identity.instrument.id ||
        buy.preview.broker.id != identity.broker.id ||
        buy.preview.funding.id != identity.funding.id) {
      throw const FormatException('Investment position identity conflict');
    }
  }
  final rows = await db
      .customSelect(
        'SELECT * FROM investment_sales WHERE workspace=? '
        'AND investment_account_id=? AND instrument_id=? ORDER BY sequence',
        variables: [
          Variable(workspace.toString()),
          Variable(investmentAccountId.value),
          Variable(instrumentId.value),
        ],
      )
      .get();
  final splitRows = db.investmentSplitsAware
      ? await db
            .customSelect(
              'SELECT * FROM investment_splits WHERE workspace=? '
              'AND investment_account_id=? AND instrument_id=? ORDER BY sequence',
              variables: [
                Variable(workspace.toString()),
                Variable(investmentAccountId.value),
                Variable(instrumentId.value),
              ],
            )
            .get()
      : <QueryRow>[];
  final actions =
      <({QueryRow row, BusinessDate date, bool split, int order})>[
        for (final row in rows)
          (
            row: row,
            date: BusinessDate.parse(
              _map(jsonDecode(row.read<String>('payload')))['tradedOn']
                  as String,
            ),
            split: false,
            order: row.read<int>('sequence'),
          ),
        for (final row in splitRows)
          (
            row: row,
            date: BusinessDate.parse(row.read<String>('effective_on')),
            split: true,
            order: row.read<int>('sequence'),
          ),
      ]..sort((a, b) {
        final date = a.date.compareTo(b.date);
        if (date != 0) return date;
        if (a.split != b.split) return a.split ? -1 : 1;
        return a.order.compareTo(b.order);
      });
  final lots = <PublicId, InvestmentHoldingLot>{};
  final sales = <InvestmentSellFact>[];
  final splits = <InvestmentSplitFact>[];
  InvestmentCostMethod? method;
  BusinessDate? lastDate;
  BusinessDate? lastSplitDate;
  var purchaseIndex = 0;
  void addPurchase(InvestmentBuyFact buy) {
    final preview = buy.preview;
    if (lots.containsKey(preview.lot.id)) {
      throw const FormatException('Duplicate investment lot');
    }
    lots[preview.lot.id] = InvestmentHoldingLot(
      id: preview.lot.id,
      investmentAccountId: preview.account.id,
      instrumentId: preview.instrument.id,
      acquiredOn: preview.tradedOn,
      remainingQuantity: preview.quantity,
      remainingCost: preview.cashDebit,
      expectedVersion: 1,
    );
  }

  for (final action in actions) {
    final row = action.row;
    while (purchaseIndex < purchases.length &&
        purchases[purchaseIndex].preview.tradedOn.compareTo(action.date) <= 0) {
      addPurchase(purchases[purchaseIndex++]);
    }
    if (action.split) {
      if (identity == null ||
          row.read<int>('sequence') != splits.length + 1 ||
          (lastDate != null && lastDate.compareTo(action.date) >= 0) ||
          (lastSplitDate != null &&
              lastSplitDate.compareTo(action.date) >= 0)) {
        throw const FormatException('Invalid investment split chronology');
      }
      splits.add(await _applySplitRow(db, row, identity, lots));
      lastSplitDate = action.date;
      continue;
    }
    if (identity == null || row.read<int>('sequence') != sales.length + 1) {
      throw const FormatException('Invalid investment sale sequence');
    }
    final payload = row.read<String>('payload');
    final data = _map(jsonDecode(payload));
    final tradedOn = action.date;
    if (lastDate != null && lastDate.compareTo(tradedOn) > 0) {
      throw const FormatException('Investment sale chronology mismatch');
    }
    if (lastSplitDate != null && lastSplitDate.compareTo(tradedOn) > 0) {
      throw const FormatException('Investment sale precedes split');
    }
    final preview = _decodeSellPreview(data, identity, lots.values.toList());
    if (jsonEncode(_sellMap(preview)) != payload ||
        row.read<String>('workspace') != workspace.toString() ||
        row.read<String>('sell_id') != preview.id.value ||
        row.read<String>('operation_id') !=
            preview.operation.operation.toString() ||
        row.read<String>('investment_account_id') !=
            investmentAccountId.value ||
        row.read<String>('instrument_id') != instrumentId.value ||
        row.read<String>('broker_id') != preview.broker.id.value ||
        row.read<String>('funding_account_id') != preview.funding.id.value ||
        row.read<String>('cost_method') != preview.costMethod.name ||
        (method != null && method != preview.costMethod)) {
      throw const FormatException('Investment sale payload mismatch');
    }
    await _validateSaleRows(db, row, preview);
    for (final allocation in preview.allocations) {
      lots.remove(allocation.lot.id);
      if (allocation.remainingQuantityUnits > BigInt.zero) {
        lots[allocation.lot.id] = InvestmentHoldingLot(
          id: allocation.lot.id,
          investmentAccountId: investmentAccountId,
          instrumentId: instrumentId,
          acquiredOn: allocation.lot.acquiredOn,
          remainingQuantity: _quantityFromUnits(
            allocation.remainingQuantityUnits,
          ),
          remainingCost: allocation.remainingCost,
          expectedVersion: allocation.lot.expectedVersion + 1,
        );
      } else if (allocation.remainingCost.minorUnits != BigInt.zero) {
        throw const FormatException('Closed investment lot retains cost');
      }
    }
    final eventId = PublicId.parse(row.read<String>('event_id'));
    sales.add(InvestmentSellFact(preview, eventId, sales.length + 1));
    method = preview.costMethod;
    lastDate = tradedOn;
  }
  while (purchaseIndex < purchases.length) {
    addPurchase(purchases[purchaseIndex++]);
  }
  return _InvestmentPosition(
    identity,
    lots,
    sales,
    splits,
    method,
    lastDate,
    lastSplitDate,
  );
}

InvestmentSellPreview _decodeSellPreview(
  Map<String, dynamic> data,
  InvestmentBuyPreview identity,
  List<InvestmentHoldingLot> lots,
) {
  try {
    if (data['version'] != 1 ||
        data['workspace'] != identity.operation.workspace.toString() ||
        data['brokerId'] != identity.broker.id.value ||
        data['accountId'] != identity.account.id.value ||
        data['instrumentId'] != identity.instrument.id.value ||
        data['fundingId'] != identity.funding.id.value) {
      throw const FormatException('Investment sale identity mismatch');
    }
    final currency = identity.instrument.tradingCurrency;
    return InvestmentSellPreview.create(
      id: PublicId.parse(data['sellId'] as String),
      operation: OperationKey(
        identity.operation.workspace,
        OperationId.parse(data['operation'] as String),
      ),
      tradedOn: BusinessDate.parse(data['tradedOn'] as String),
      broker: identity.broker,
      account: InvestmentAccount(
        id: identity.account.id,
        workspace: identity.account.workspace,
        brokerId: identity.account.brokerId,
        fundingCashAccountId: identity.account.fundingCashAccountId,
        name: identity.account.name,
        expectedVersion: data['accountVersion'] as int,
      ),
      instrument: identity.instrument,
      funding: FundingCashAccount(
        id: identity.funding.id,
        workspace: identity.funding.workspace,
        currency: identity.funding.currency,
        expectedVersion: data['fundingVersion'] as int,
      ),
      costMethod: InvestmentCostMethod.values.byName(
        data['costMethod'] as String,
      ),
      quantity: ShareQuantity.parse(data['quantity'] as String),
      unitPrice: ShareUnitPrice.parse(currency, data['unitPrice'] as String),
      executedGross: Money(currency, BigInt.parse(data['gross'] as String)),
      fee: Money(currency, BigInt.parse(data['fee'] as String)),
      tax: Money(currency, BigInt.parse(data['tax'] as String)),
      lots: lots,
    );
  } catch (_) {
    throw const FormatException('Invalid investment sale payload');
  }
}

Future<void> _validateSaleRows(
  ProbeDatabase db,
  QueryRow row,
  InvestmentSellPreview preview,
) async {
  final ws = preview.operation.workspace.toString();
  final eventId = row.read<String>('event_id');
  final allocations = await db
      .customSelect(
        'SELECT * FROM investment_sale_allocations '
        'WHERE workspace=? AND sell_id=? ORDER BY ordinal',
        variables: [Variable(ws), Variable(preview.id.value)],
      )
      .get();
  if (allocations.length != preview.allocations.length) {
    throw const FormatException('Investment sale allocation count mismatch');
  }
  for (var index = 0; index < allocations.length; index++) {
    final actual = allocations[index];
    final expected = preview.allocations[index];
    if (actual.read<String>('lot_id') != expected.lot.id.value ||
        actual.read<int>('ordinal') != index ||
        actual.read<String>('sold_quantity_units') !=
            expected.soldQuantityUnits.toString() ||
        actual.read<int>('allocated_cost') !=
            expected.allocatedSaleCost.minorUnits.toInt() ||
        actual.read<String>('remaining_quantity_units') !=
            expected.remainingQuantityUnits.toString() ||
        actual.read<int>('remaining_cost') !=
            expected.remainingCost.minorUnits.toInt() ||
        actual.read<int>('prior_version') != expected.lot.expectedVersion) {
      throw const FormatException('Investment sale allocation mismatch');
    }
  }
  final event = await db
      .customSelect(
        'SELECT * FROM events WHERE workspace=? AND id=?',
        variables: [Variable(ws), Variable(eventId)],
      )
      .getSingleOrNull();
  final legs = await db
      .customSelect(
        'SELECT * FROM legs WHERE workspace=? AND event_id=?',
        variables: [Variable(ws), Variable(eventId)],
      )
      .get();
  final receipt = await db
      .customSelect(
        'SELECT r.input,r.result_id,a.entity_id,a.kind FROM receipts r '
        'LEFT JOIN audit a ON a.workspace=r.workspace AND a.operation_id=r.operation_id '
        'WHERE r.workspace=? AND r.operation_id=?',
        variables: [
          Variable(ws),
          Variable(preview.operation.operation.toString()),
        ],
      )
      .getSingleOrNull();
  if (event == null || legs.length != 1 || receipt == null) {
    throw const FormatException('Investment sale Ledger link missing');
  }
  final leg = legs.single;
  final expectedReceipt = jsonEncode([
    'investment-sell-v1',
    eventId,
    jsonEncode(_sellMap(preview)),
  ]);
  if (event.read<String>('kind') != 'investmentSell' ||
      event.read<String>('business_date') != preview.tradedOn.toString() ||
      event.read<int>('income') != 0 ||
      event.read<int>('expense') != 0 ||
      event.read<String>('source_context') != 'investment-sell-v1' ||
      event.read<String>('currency') != preview.cashCredit.currency.code ||
      event.read<int>('scale') != preview.cashCredit.currency.scale ||
      leg.read<int>('ordinal') != 0 ||
      leg.read<String>('account_id') != preview.funding.id.value ||
      leg.read<int>('amount') != preview.cashCredit.minorUnits.toInt() ||
      leg.read<String>('currency') != preview.cashCredit.currency.code ||
      leg.read<int>('scale') != preview.cashCredit.currency.scale ||
      leg.read<String>('role') != 'principal' ||
      receipt.read<String>('input') != expectedReceipt ||
      receipt.read<String>('result_id') != eventId ||
      receipt.read<String?>('entity_id') != eventId ||
      receipt.read<String?>('kind') != 'ledger.investmentSell') {
    throw const FormatException('Investment sale Ledger fact mismatch');
  }
}

ShareQuantity _quantityFromUnits(BigInt units) {
  if (units <= BigInt.zero) {
    throw const FormatException('Investment lot quantity must stay positive');
  }
  final base = BigInt.from(10).pow(12);
  final whole = units ~/ base;
  final fraction = (units % base)
      .toString()
      .padLeft(12, '0')
      .replaceFirst(RegExp(r'0+$'), '');
  return ShareQuantity.parse(fraction.isEmpty ? '$whole' : '$whole.$fraction');
}
