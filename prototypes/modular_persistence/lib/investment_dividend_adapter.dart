part of 'investment_adapter.dart';

final class InvestmentDividendFact {
  const InvestmentDividendFact(this.preview, this.eventId);
  final InvestmentDividendPreview preview;
  final PublicId eventId;
}

/// The only schema-23 dividend entry. Its cash event, immutable investment
/// fact, receipt, and audit are committed in one SQLite transaction.
Future<CommitResult> commitInvestmentDividend(
  ProbeDatabase db,
  InvestmentDividendPreview preview,
  Posting posting, {
  void Function(String)? checkpoint,
}) => db.transaction(() async {
  _requireDividendSchema(db);
  _requireDividendPosting(preview, posting);
  final payload = const InvestmentDividendPreviewCodec().encode(preview);
  final receipt = jsonEncode([
    'investment-dividend-v1',
    posting.id.value,
    payload,
  ]);
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
          'Dividend settlement requires cash or bank',
        );
      }
      funding.requirePosting(
        workspace: preview.operation.workspace,
        currency: preview.netCashCredit.currency,
        expectedVersion: preview.funding.expectedVersion,
        date: preview.paidOn,
      );
      await _requireDividendIdentity(db, preview);
      await LedgerAdapter(
        db,
        sourceContext: 'investment-dividend-v1',
      ).insert(posting, checkpoint: checkpoint);
      checkpoint?.call('investmentDividendEvent');
      await db.customStatement(
        'INSERT INTO investment_dividends VALUES (?,?,?,?,?,?,?,?,?)',
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
      checkpoint?.call('investmentDividend');
      await LedgerAdapter(db).balance(posting.legs.single.account);
    },
    'ledger.investmentDividend',
    checkpoint,
  );
  if (result.id != posting.id) throw OperationConflict();
  final row = await db
      .customSelect(
        'SELECT * FROM investment_dividends WHERE workspace=? AND dividend_id=?',
        variables: [
          Variable(preview.operation.workspace.toString()),
          Variable(preview.id.value),
        ],
      )
      .getSingleOrNull();
  if (row == null ||
      row.read<String>('payload') != payload ||
      row.read<String>('event_id') != posting.id.value) {
    throw OperationConflict();
  }
  await _validateDividendFact(db, row);
  return result;
});

Future<List<InvestmentDividendFact>> investmentDividends(
  ProbeDatabase db,
  WorkspaceId workspace, [
  PublicId? investmentAccountId,
]) async {
  _requireDividendSchema(db);
  final rows = await db
      .customSelect(
        investmentAccountId == null
            ? 'SELECT * FROM investment_dividends WHERE workspace=? ORDER BY dividend_id'
            : 'SELECT * FROM investment_dividends WHERE workspace=? AND investment_account_id=? ORDER BY dividend_id',
        variables: [
          Variable(workspace.toString()),
          if (investmentAccountId != null) Variable(investmentAccountId.value),
        ],
      )
      .get();
  final facts = <InvestmentDividendFact>[];
  for (final row in rows) {
    facts.add(await _validateDividendFact(db, row));
  }
  return List.unmodifiable(facts);
}

/// Complete authority check, including orphan cash events and audits.
Future<void> validateInvestmentDividendFacts(ProbeDatabase db) async {
  _requireDividendSchema(db);
  await validateInvestmentSaleFacts(db);
  final rows = await db
      .customSelect('SELECT * FROM investment_dividends')
      .get();
  for (final row in rows) {
    await _validateDividendFact(db, row);
  }
  final orphanEvents = await db
      .customSelect(
        "SELECT e.id FROM events e LEFT JOIN investment_dividends d "
        "ON d.workspace=e.workspace AND d.event_id=e.id "
        "WHERE e.kind='investmentDividend' AND d.dividend_id IS NULL LIMIT 1",
      )
      .get();
  final orphanAudits = await db
      .customSelect(
        "SELECT a.operation_id FROM audit a LEFT JOIN investment_dividends d "
        "ON d.workspace=a.workspace AND d.operation_id=a.operation_id "
        "WHERE a.kind='ledger.investmentDividend' AND d.dividend_id IS NULL LIMIT 1",
      )
      .get();
  if (orphanEvents.isNotEmpty || orphanAudits.isNotEmpty) {
    throw const FormatException('Orphan investment dividend fact');
  }
}

void _requireDividendSchema(ProbeDatabase db) {
  if (!db.investmentDividendsAware) {
    throw const FormatException('Investment dividend schema unavailable');
  }
}

void _requireDividendPosting(
  InvestmentDividendPreview preview,
  Posting posting,
) {
  final cash = posting.investmentDividend;
  final leg = posting.legs.singleOrNull;
  final ids = [
    preview.id,
    posting.id,
    preview.broker.id,
    preview.account.id,
    preview.instrument.id,
    preview.funding.id,
  ];
  if (ids.toSet().length != ids.length ||
      posting.kind != PostingKind.investmentDividend ||
      posting.operation != preview.operation ||
      posting.date != preview.paidOn ||
      cash == null ||
      cash.dividendId != preview.id ||
      cash.gross != preview.gross ||
      cash.withholdingTax != preview.withholdingTax ||
      cash.fee != preview.fee ||
      cash.cashCredit != preview.netCashCredit ||
      leg == null ||
      leg.account.id != preview.funding.id ||
      leg.account.workspace != preview.funding.workspace ||
      leg.account.expectedVersion != preview.funding.expectedVersion ||
      leg.account.currency != preview.funding.currency ||
      leg.amount != preview.netCashCredit ||
      leg.role != LegRole.principal ||
      posting.reportIncome.minorUnits != BigInt.zero ||
      posting.reportExpense.minorUnits != BigInt.zero ||
      posting.allocations.isNotEmpty) {
    throw const FormatException('Investment dividend posting mismatch');
  }
}

Future<void> _requireDividendIdentity(
  ProbeDatabase db,
  InvestmentDividendPreview preview,
) async {
  final buys = await investmentBuys(
    db,
    preview.operation.workspace,
    preview.account.id,
  );
  final matches = buys.where((fact) {
    final buy = fact.preview;
    return buy.instrument.id == preview.instrument.id &&
        buy.tradedOn.compareTo(preview.paidOn) <= 0 &&
        buy.broker.id == preview.broker.id &&
        buy.broker.name == preview.broker.name &&
        buy.account.id == preview.account.id &&
        buy.account.name == preview.account.name &&
        buy.account.expectedVersion == preview.account.expectedVersion &&
        buy.funding.id == preview.funding.id &&
        buy.instrument.kind == preview.instrument.kind &&
        buy.instrument.marketCode == preview.instrument.marketCode &&
        buy.instrument.symbol == preview.instrument.symbol &&
        buy.instrument.name == preview.instrument.name &&
        buy.instrument.tradingCurrency == preview.instrument.tradingCurrency;
  });
  if (matches.isEmpty) {
    throw const FormatException('Dividend requires an existing position');
  }
}

Future<InvestmentDividendFact> _validateDividendFact(
  ProbeDatabase db,
  QueryRow row,
) async {
  final payload = row.read<String>('payload');
  final preview = const InvestmentDividendPreviewCodec().decode(payload);
  final ws = preview.operation.workspace.toString();
  final eventId = row.read<String>('event_id');
  if (row.read<String>('workspace') != ws ||
      row.read<String>('dividend_id') != preview.id.value ||
      row.read<String>('operation_id') !=
          preview.operation.operation.toString() ||
      row.read<String>('investment_account_id') != preview.account.id.value ||
      row.read<String>('instrument_id') != preview.instrument.id.value ||
      row.read<String>('broker_id') != preview.broker.id.value ||
      row.read<String>('funding_account_id') != preview.funding.id.value) {
    throw const FormatException('Investment dividend identity mismatch');
  }
  await _requireDividendIdentity(db, preview);
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
    throw const FormatException('Dividend Ledger link missing');
  }
  final leg = legs.single;
  final expectedReceipt = jsonEncode([
    'investment-dividend-v1',
    eventId,
    payload,
  ]);
  if (event.read<String>('kind') != 'investmentDividend' ||
      event.read<String>('business_date') != preview.paidOn.toString() ||
      event.read<int>('income') != 0 ||
      event.read<int>('expense') != 0 ||
      event.read<String>('source_context') != 'investment-dividend-v1' ||
      event.read<String>('currency') != preview.netCashCredit.currency.code ||
      event.read<int>('scale') != preview.netCashCredit.currency.scale ||
      leg.read<int>('ordinal') != 0 ||
      leg.read<String>('account_id') != preview.funding.id.value ||
      leg.read<int>('amount') != preview.netCashCredit.minorUnits.toInt() ||
      leg.read<String>('currency') != preview.netCashCredit.currency.code ||
      leg.read<int>('scale') != preview.netCashCredit.currency.scale ||
      leg.read<String>('role') != 'principal' ||
      receipt.read<String>('input') != expectedReceipt ||
      receipt.read<String>('result_id') != eventId ||
      receipt.read<String?>('entity_id') != eventId ||
      receipt.read<String?>('kind') != 'ledger.investmentDividend') {
    throw const FormatException('Investment dividend Ledger fact mismatch');
  }
  return InvestmentDividendFact(preview, PublicId.parse(eventId));
}
