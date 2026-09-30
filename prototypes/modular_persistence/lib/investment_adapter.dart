import 'dart:convert';

import 'package:accounts/accounts.dart';
import 'package:drift/drift.dart' show QueryRow, Variable;
import 'package:foundation_values/foundation_values.dart';
import 'package:investments/investments.dart';
import 'package:ledger/ledger.dart';

import 'adapters.dart';
import 'database.dart';
import 'operations.dart';

part 'investment_sale_adapter.dart';
part 'investment_dividend_adapter.dart';
part 'investment_split_adapter.dart';

/// An immutable buy and its one acquisition lot, backed by a committed Ledger
/// cash debit. This does not provide sell, valuation, or tax-basis semantics.
final class InvestmentBuyFact {
  const InvestmentBuyFact(this.preview, this.eventId);
  final InvestmentBuyPreview preview;
  final PublicId eventId;
}

/// The only schema-21 entry point for a buy. The receipt, cash leg, identity
/// rows, buy, and lot are committed in one transaction; retry verifies all of
/// them before it is reported as a replay.
Future<CommitResult> commitInvestmentBuy(
  ProbeDatabase db,
  InvestmentBuyPreview preview,
  Posting posting, {
  void Function(String)? checkpoint,
}) => db.transaction(() async {
  _requireSchema(db);
  _requirePosting(preview, posting);
  final payload = jsonEncode(_previewMap(preview));
  final result = await OperationWriter(db).commit(
    preview.operation,
    _receiptInput(preview, posting.id),
    posting.id,
    () async {
      final funding = await AccountsAdapter(db)
          .read(preview.operation.workspace, preview.funding.id);
      if (funding.kind != AccountKind.cash &&
          funding.kind != AccountKind.bank) {
        throw const FormatException(
          'Investment funding account must be cash or bank',
        );
      }
      funding.requirePosting(
        workspace: preview.operation.workspace,
        currency: preview.cashDebit.currency,
        expectedVersion: preview.funding.expectedVersion,
        date: preview.tradedOn,
      );
      if (db.investmentSalesAware) {
        final position = await _loadPosition(
          db,
          preview.operation.workspace,
          preview.account.id,
          preview.instrument.id,
        );
        // A later purchase cannot be inserted into an earlier disposition's
        // full-lot snapshot. The next business date keeps replay unambiguous.
        if (position.lastDate != null &&
            preview.tradedOn.compareTo(position.lastDate!) <= 0) {
          throw const FormatException(
            'Investment buy must follow the last sale date',
          );
        }
        if (db.investmentSplitsAware &&
            position.lastSplitDate != null &&
            preview.tradedOn.compareTo(position.lastSplitDate!) <= 0) {
          throw const FormatException(
            'Investment buy must follow the last split date',
          );
        }
      }
      await _storeIdentities(db, preview);
      await LedgerAdapter(
        db,
        sourceContext: 'investment-buy-v1',
      ).insert(posting, checkpoint: checkpoint);
      checkpoint?.call('investmentEvent');
      await db.customStatement(
        'INSERT INTO investment_buys VALUES (?,?,?,?,?,?,?,?,?)',
        [
          preview.operation.workspace.toString(),
          preview.id.value,
          preview.operation.operation.toString(),
          posting.id.value,
          preview.account.id.value,
          preview.instrument.id.value,
          preview.broker.id.value,
          preview.funding.id.value,
          payload,
        ],
      );
      checkpoint?.call('investmentBuy');
      await db.customStatement(
        'INSERT INTO investment_lots VALUES (?,?,?,?,?,?)',
        [
          preview.operation.workspace.toString(),
          preview.lot.id.value,
          preview.id.value,
          preview.account.id.value,
          preview.instrument.id.value,
          jsonEncode(_lotMap(preview)),
        ],
      );
      checkpoint?.call('investmentLot');
      await LedgerAdapter(db).balance(posting.legs.single.account);
    },
    'ledger.investmentBuy',
    checkpoint,
  );
  if (result.id != posting.id) throw OperationConflict();
  final saved = await _buyById(
    db,
    preview.operation.workspace.toString(),
    preview.id.value,
  );
  if (saved == null ||
      saved.read<String>('payload') != payload ||
      saved.read<String>('event_id') != posting.id.value) {
    throw OperationConflict();
  }
  await _validateFact(db, saved);
  return result;
});

/// Reads only facts proven to have the matching cash event and receipt.
Future<List<InvestmentBuyFact>> investmentBuys(
  ProbeDatabase db,
  WorkspaceId workspace, [
  PublicId? investmentAccountId,
]) async {
  _requireSchema(db);
  final rows = await db
      .customSelect(
        investmentAccountId == null
            ? 'SELECT * FROM investment_buys WHERE workspace=? ORDER BY buy_id'
            : 'SELECT * FROM investment_buys WHERE workspace=? AND investment_account_id=? ORDER BY buy_id',
        variables: [
          Variable(workspace.toString()),
          if (investmentAccountId != null) Variable(investmentAccountId.value),
        ],
      )
      .get();
  final facts = <InvestmentBuyFact>[];
  for (final row in rows) {
    facts.add(await _validateFact(db, row));
  }
  return List.unmodifiable(facts);
}

/// Run on snapshot capture and restore before publishing a generation. Every
/// investment event must have exactly one buy and lot, and every buy must have
/// the exact operation receipt, audit, identities, and cash leg.
Future<void> validateInvestmentFacts(ProbeDatabase db) async {
  _requireSchema(db);
  final buys = await db.customSelect('SELECT * FROM investment_buys').get();
  for (final buy in buys) {
    await _validateFact(db, buy);
  }
  final orphanEvents = await db
      .customSelect(
        "SELECT e.id FROM events e LEFT JOIN investment_buys b "
        "ON b.workspace=e.workspace AND b.event_id=e.id "
        "WHERE e.kind='investmentBuy' AND b.buy_id IS NULL LIMIT 1",
      )
      .get();
  final orphanLots = await db
      .customSelect(
        'SELECT l.lot_id FROM investment_lots l LEFT JOIN investment_buys b '
        'ON b.workspace=l.workspace AND b.buy_id=l.buy_id '
        'WHERE b.buy_id IS NULL LIMIT 1',
      )
      .get();
  final orphanAudits = await db
      .customSelect(
        "SELECT a.operation_id FROM audit a LEFT JOIN investment_buys b "
        "ON b.workspace=a.workspace AND b.operation_id=a.operation_id "
        "WHERE a.kind='ledger.investmentBuy' AND b.buy_id IS NULL LIMIT 1",
      )
      .get();
  if (orphanEvents.isNotEmpty ||
      orphanLots.isNotEmpty ||
      orphanAudits.isNotEmpty) {
    throw const FormatException('Orphan investment fact');
  }
}

void _requireSchema(ProbeDatabase db) {
  if (!db.investmentsAware) {
    throw const FormatException('Investment schema unavailable');
  }
}

void _requirePosting(InvestmentBuyPreview preview, Posting posting) {
  final leg = posting.legs.singleOrNull;
  final cash = posting.investmentBuy;
  final ids = [
    preview.id,
    preview.lot.id,
    posting.id,
    preview.broker.id,
    preview.account.id,
    preview.instrument.id,
    preview.funding.id,
  ];
  if (ids.toSet().length != ids.length ||
      posting.kind != PostingKind.investmentBuy ||
      posting.operation != preview.operation ||
      posting.date != preview.tradedOn ||
      cash == null ||
      cash.buyId != preview.id ||
      cash.gross != preview.gross ||
      cash.fee != preview.fee ||
      cash.tax != preview.tax ||
      cash.cashDebit != preview.cashDebit ||
      leg == null ||
      leg.account.id != preview.funding.id ||
      leg.account.workspace != preview.operation.workspace ||
      leg.account.expectedVersion != preview.funding.expectedVersion ||
      leg.account.currency != preview.funding.currency ||
      leg.role != LegRole.principal ||
      leg.amount != -preview.cashDebit ||
      posting.reportIncome.minorUnits != BigInt.zero ||
      posting.reportExpense.minorUnits != BigInt.zero ||
      posting.allocations.isNotEmpty) {
    throw const FormatException('Investment buy posting mismatch');
  }
}

String _receiptInput(InvestmentBuyPreview preview, PublicId eventId) =>
    jsonEncode(['investment-buy-v1', eventId.value, _previewMap(preview)]);

Map<String, Object> _previewMap(InvestmentBuyPreview preview) => {
  'version': 1,
  'workspace': preview.operation.workspace.toString(),
  'operation': preview.operation.operation.toString(),
  'buyId': preview.id.value,
  'lotId': preview.lot.id.value,
  'tradedOn': preview.tradedOn.toString(),
  'broker': {'id': preview.broker.id.value, 'name': preview.broker.name},
  'account': {
    'id': preview.account.id.value,
    'brokerId': preview.account.brokerId.value,
    'fundingAccountId': preview.account.fundingCashAccountId.value,
    'name': preview.account.name,
    'expectedVersion': preview.account.expectedVersion,
  },
  'instrument': {
    'id': preview.instrument.id.value,
    'kind': preview.instrument.kind.name,
    'marketCode': preview.instrument.marketCode,
    'symbol': preview.instrument.symbol,
    'name': preview.instrument.name,
    'currency': preview.instrument.tradingCurrency.code,
    'scale': preview.instrument.tradingCurrency.scale,
  },
  'funding': {
    'id': preview.funding.id.value,
    'currency': preview.funding.currency.code,
    'scale': preview.funding.currency.scale,
    'expectedVersion': preview.funding.expectedVersion,
  },
  'quantity': preview.quantity.toString(),
  'unitPrice': preview.unitPrice.toString(),
  'gross': preview.gross.minorUnits.toString(),
  'fee': preview.fee.minorUnits.toString(),
  'tax': preview.tax.minorUnits.toString(),
  'cashDebit': preview.cashDebit.minorUnits.toString(),
};

Map<String, Object> _lotMap(InvestmentBuyPreview preview) => {
  'version': 1,
  'lotId': preview.lot.id.value,
  'buyId': preview.id.value,
  'investmentAccountId': preview.account.id.value,
  'instrumentId': preview.instrument.id.value,
  'acquiredOn': preview.tradedOn.toString(),
  'quantity': preview.quantity.toString(),
  'unitPrice': preview.unitPrice.toString(),
  'gross': preview.gross.minorUnits.toString(),
  'fee': preview.fee.minorUnits.toString(),
  'tax': preview.tax.minorUnits.toString(),
  'acquisitionCashCost': preview.cashDebit.minorUnits.toString(),
};

Future<void> _storeIdentities(
  ProbeDatabase db,
  InvestmentBuyPreview preview,
) async {
  final ws = preview.operation.workspace.toString();
  await _insertOrMatch(
    db,
    'investment_brokers',
    [ws, preview.broker.id.value, preview.broker.name],
    ['workspace', 'id', 'name'],
  );
  await _insertOrMatch(
    db,
    'investment_accounts',
    [
      ws,
      preview.account.id.value,
      preview.broker.id.value,
      preview.funding.id.value,
      preview.account.name,
      preview.account.expectedVersion,
    ],
    ['workspace', 'id', 'broker_id', 'funding_account_id', 'name', 'version'],
  );
  await _insertOrMatch(
    db,
    'investment_instruments',
    [
      ws,
      preview.instrument.id.value,
      preview.instrument.kind.name,
      preview.instrument.marketCode,
      preview.instrument.symbol,
      preview.instrument.name,
      preview.instrument.tradingCurrency.code,
      preview.instrument.tradingCurrency.scale,
    ],
    [
      'workspace',
      'id',
      'kind',
      'market_code',
      'symbol',
      'name',
      'currency',
      'scale',
    ],
  );
}

Future<void> _insertOrMatch(
  ProbeDatabase db,
  String table,
  List<Object> values,
  List<String> columns,
) async {
  // Table and column names come only from the literal internal call sites.
  final rows = await db
      .customSelect(
        'SELECT * FROM $table WHERE workspace=? AND id=?',
        variables: [Variable(values[0]), Variable(values[1])],
      )
      .get();
  if (rows.isEmpty) {
    await db.customStatement(
      'INSERT INTO $table VALUES (${List.filled(values.length, '?').join(',')})',
      values,
    );
  } else if (rows.length != 1 ||
      List.generate(
        columns.length,
        (i) => rows.single.data[columns[i]] == values[i],
      ).contains(false)) {
    throw const FormatException('Investment identity conflict');
  }
}

Future<QueryRow?> _buyById(ProbeDatabase db, String ws, String buyId) => db
    .customSelect(
      'SELECT * FROM investment_buys WHERE workspace=? AND buy_id=?',
      variables: [Variable(ws), Variable(buyId)],
    )
    .getSingleOrNull();

InvestmentBuyPreview _decodePreview(String payload) {
  try {
    final data = _map(jsonDecode(payload));
    if (data['version'] != 1)
      throw const FormatException('Investment payload version');
    final workspace = WorkspaceId.parse(data['workspace'] as String);
    final operation = OperationKey(
      workspace,
      OperationId.parse(data['operation'] as String),
    );
    final brokerData = _map(data['broker']);
    final accountData = _map(data['account']);
    final instrumentData = _map(data['instrument']);
    final fundingData = _map(data['funding']);
    final currency = Currency(
      instrumentData['currency'] as String,
      instrumentData['scale'] as int,
    );
    final preview = InvestmentBuyPreview.create(
      id: PublicId.parse(data['buyId'] as String),
      lotId: PublicId.parse(data['lotId'] as String),
      operation: operation,
      tradedOn: BusinessDate.parse(data['tradedOn'] as String),
      broker: BrokerIdentity(
        id: PublicId.parse(brokerData['id'] as String),
        workspace: workspace,
        name: brokerData['name'] as String,
      ),
      account: InvestmentAccount(
        id: PublicId.parse(accountData['id'] as String),
        workspace: workspace,
        brokerId: PublicId.parse(accountData['brokerId'] as String),
        fundingCashAccountId: PublicId.parse(
          accountData['fundingAccountId'] as String,
        ),
        name: accountData['name'] as String,
        expectedVersion: accountData['expectedVersion'] as int,
      ),
      instrument: InvestmentInstrument(
        id: PublicId.parse(instrumentData['id'] as String),
        kind: InstrumentKind.values.byName(instrumentData['kind'] as String),
        marketCode: instrumentData['marketCode'] as String,
        symbol: instrumentData['symbol'] as String,
        name: instrumentData['name'] as String,
        tradingCurrency: currency,
      ),
      funding: FundingCashAccount(
        id: PublicId.parse(fundingData['id'] as String),
        workspace: workspace,
        currency: Currency(
          fundingData['currency'] as String,
          fundingData['scale'] as int,
        ),
        expectedVersion: fundingData['expectedVersion'] as int,
      ),
      quantity: ShareQuantity.parse(data['quantity'] as String),
      unitPrice: ShareUnitPrice.parse(currency, data['unitPrice'] as String),
      executedGross: Money(currency, BigInt.parse(data['gross'] as String)),
      fee: Money(currency, BigInt.parse(data['fee'] as String)),
      tax: Money(currency, BigInt.parse(data['tax'] as String)),
    );
    if (preview.cashDebit.minorUnits.toString() != data['cashDebit'] ||
        jsonEncode(_previewMap(preview)) != payload) {
      throw const FormatException('Investment payload mismatch');
    }
    return preview;
  } catch (_) {
    throw const FormatException('Invalid investment buy payload');
  }
}

Map<String, dynamic> _map(Object? value) {
  if (value is! Map) throw const FormatException('Invalid investment payload');
  return Map<String, dynamic>.from(value);
}

Future<InvestmentBuyFact> _validateFact(ProbeDatabase db, QueryRow row) async {
  final preview = _decodePreview(row.read<String>('payload'));
  final ws = preview.operation.workspace.toString();
  final eventId = PublicId.parse(row.read<String>('event_id'));
  if (row.read<String>('workspace') != ws ||
      row.read<String>('buy_id') != preview.id.value ||
      row.read<String>('operation_id') !=
          preview.operation.operation.toString() ||
      row.read<String>('investment_account_id') != preview.account.id.value ||
      row.read<String>('instrument_id') != preview.instrument.id.value ||
      row.read<String>('broker_id') != preview.broker.id.value ||
      row.read<String>('funding_account_id') != preview.funding.id.value) {
    throw const FormatException('Investment buy identity mismatch');
  }
  await _requireIdentityRows(db, preview);
  final lotRows = await db
      .customSelect(
        'SELECT * FROM investment_lots WHERE workspace=? AND buy_id=?',
        variables: [Variable(ws), Variable(preview.id.value)],
      )
      .get();
  if (lotRows.length != 1 ||
      lotRows.single.read<String>('lot_id') != preview.lot.id.value ||
      lotRows.single.read<String>('investment_account_id') !=
          preview.account.id.value ||
      lotRows.single.read<String>('instrument_id') !=
          preview.instrument.id.value ||
      lotRows.single.read<String>('payload') != jsonEncode(_lotMap(preview))) {
    throw const FormatException('Investment lot mismatch');
  }
  final events = await db
      .customSelect(
        'SELECT * FROM events WHERE workspace=? AND id=?',
        variables: [Variable(ws), Variable(eventId.value)],
      )
      .get();
  final legs = await db
      .customSelect(
        'SELECT * FROM legs WHERE workspace=? AND event_id=?',
        variables: [Variable(ws), Variable(eventId.value)],
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
      .get();
  if (events.length != 1 || legs.length != 1 || receipt.length != 1) {
    throw const FormatException('Investment Ledger link missing');
  }
  final event = events.single;
  final leg = legs.single;
  final operation = receipt.single;
  if (event.read<String>('kind') != 'investmentBuy' ||
      event.read<String>('business_date') != preview.tradedOn.toString() ||
      event.read<int>('income') != 0 ||
      event.read<int>('expense') != 0 ||
      event.read<String>('currency') != preview.cashDebit.currency.code ||
      event.read<int>('scale') != preview.cashDebit.currency.scale ||
      event.read<String>('source_context') != 'investment-buy-v1' ||
      leg.read<int>('ordinal') != 0 ||
      leg.read<String>('account_id') != preview.funding.id.value ||
      leg.read<int>('amount') != -preview.cashDebit.minorUnits.toInt() ||
      leg.read<String>('currency') != preview.cashDebit.currency.code ||
      leg.read<int>('scale') != preview.cashDebit.currency.scale ||
      leg.read<String>('role') != 'principal' ||
      operation.read<String>('input') != _receiptInput(preview, eventId) ||
      operation.read<String>('result_id') != eventId.value ||
      operation.read<String?>('entity_id') != eventId.value ||
      operation.read<String?>('kind') != 'ledger.investmentBuy') {
    throw const FormatException('Investment Ledger fact mismatch');
  }
  return InvestmentBuyFact(preview, eventId);
}

Future<void> _requireIdentityRows(
  ProbeDatabase db,
  InvestmentBuyPreview preview,
) async {
  final ws = preview.operation.workspace.toString();
  final broker = await db
      .customSelect(
        'SELECT name FROM investment_brokers WHERE workspace=? AND id=?',
        variables: [Variable(ws), Variable(preview.broker.id.value)],
      )
      .get();
  final account = await db
      .customSelect(
        'SELECT * FROM investment_accounts WHERE workspace=? AND id=?',
        variables: [Variable(ws), Variable(preview.account.id.value)],
      )
      .get();
  final instrument = await db
      .customSelect(
        'SELECT * FROM investment_instruments WHERE workspace=? AND id=?',
        variables: [Variable(ws), Variable(preview.instrument.id.value)],
      )
      .get();
  if (broker.length != 1 ||
      account.length != 1 ||
      instrument.length != 1 ||
      broker.single.read<String>('name') != preview.broker.name ||
      account.single.read<String>('broker_id') != preview.broker.id.value ||
      account.single.read<String>('funding_account_id') !=
          preview.funding.id.value ||
      account.single.read<String>('name') != preview.account.name ||
      account.single.read<int>('version') != preview.account.expectedVersion ||
      instrument.single.read<String>('kind') != preview.instrument.kind.name ||
      instrument.single.read<String>('market_code') !=
          preview.instrument.marketCode ||
      instrument.single.read<String>('symbol') != preview.instrument.symbol ||
      instrument.single.read<String>('name') != preview.instrument.name ||
      instrument.single.read<String>('currency') !=
          preview.instrument.tradingCurrency.code ||
      instrument.single.read<int>('scale') !=
          preview.instrument.tradingCurrency.scale) {
    throw const FormatException('Investment identity mismatch');
  }
  final funding = await AccountsAdapter(db)
      .read(preview.operation.workspace, preview.funding.id);
  if ((funding.kind != AccountKind.cash && funding.kind != AccountKind.bank) ||
      funding.currency != preview.funding.currency) {
    throw const FormatException('Investment funding identity mismatch');
  }
}
