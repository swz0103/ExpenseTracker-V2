part of 'investment_adapter.dart';

final class InvestmentSplitFact {
  const InvestmentSplitFact(this.preview, this.sequence);
  final StockSplitPreview preview;
  final int sequence;
}

/// Saves the corporate action and every exact lot change with one receipt.
/// No cash Ledger event, income or expense is created.
Future<CommitResult> commitInvestmentSplit(
  ProbeDatabase db,
  StockSplitPreview preview, {
  void Function(String)? checkpoint,
}) => db.transaction(() async {
  _requireSplitSchema(db);
  final payload = const StockSplitPreviewCodec().encode(preview);
  final result = await OperationWriter(db).commit(
    preview.operation,
    jsonEncode(['investment-split-v1', preview.id.value, payload]),
    preview.id,
    () async {
      final position = await _loadPosition(
        db,
        preview.operation.workspace,
        preview.account.id,
        preview.instrument.id,
      );
      final identity = position.identity;
      if (identity == null || !_matchesSplitIdentity(preview, identity)) {
        throw const FormatException('Investment split identity mismatch');
      }
      if ((position.lastDate != null &&
              position.lastDate!.compareTo(preview.effectiveOn) >= 0) ||
          (position.lastSplitDate != null &&
              position.lastSplitDate!.compareTo(preview.effectiveOn) >= 0)) {
        throw const FormatException('Split cannot rewrite prior sale history');
      }
      preview.verifyCurrentLots(position.lots.values.toList());
      final workspace = preview.operation.workspace.toString();
      final collidingEvent = await db
          .customSelect(
            'SELECT id FROM events WHERE workspace=? AND id=?',
            variables: [Variable(workspace), Variable(preview.id.value)],
          )
          .getSingleOrNull();
      if (collidingEvent != null) {
        throw const FormatException('Split ID collides with cash event');
      }
      await db.customStatement(
        'INSERT INTO investment_splits VALUES (?,?,?,?,?,?,?,?,?)',
        [
          workspace,
          preview.id.value,
          preview.operation.operation.toString(),
          preview.account.id.value,
          preview.instrument.id.value,
          preview.broker.id.value,
          preview.effectiveOn.toString(),
          position.splitCount + 1,
          payload,
        ],
      );
      checkpoint?.call('investmentSplit');
      for (var index = 0; index < preview.lots.length; index++) {
        final change = preview.lots[index];
        await db.customStatement(
          'INSERT INTO investment_split_lots VALUES (?,?,?,?,?,?,?,?)',
          [
            workspace,
            preview.id.value,
            change.before.id.value,
            index,
            _splitUnits(change.before.remainingQuantity).toString(),
            _splitUnits(change.afterQuantity).toString(),
            change.before.remainingCost.minorUnits.toInt(),
            change.before.expectedVersion,
          ],
        );
        checkpoint?.call('investmentSplitLot');
      }
    },
    'investment.split-v1',
    checkpoint,
  );
  if (result.id != preview.id) throw OperationConflict();
  final position = await _loadPosition(
    db,
    preview.operation.workspace,
    preview.account.id,
    preview.instrument.id,
  );
  if (!position.splits.any(
    (fact) =>
        fact.preview.id == preview.id &&
        const StockSplitPreviewCodec().encode(fact.preview) == payload,
  )) {
    throw OperationConflict();
  }
  return result;
});

Future<List<InvestmentSplitFact>> investmentSplits(
  ProbeDatabase db,
  WorkspaceId workspace, [
  PublicId? investmentAccountId,
]) async {
  _requireSplitSchema(db);
  final positions = await db
      .customSelect(
        investmentAccountId == null
            ? 'SELECT DISTINCT investment_account_id,instrument_id FROM investment_splits WHERE workspace=?'
            : 'SELECT DISTINCT investment_account_id,instrument_id FROM investment_splits WHERE workspace=? AND investment_account_id=?',
        variables: [
          Variable(workspace.toString()),
          if (investmentAccountId != null) Variable(investmentAccountId.value),
        ],
      )
      .get();
  final facts = <InvestmentSplitFact>[];
  for (final row in positions) {
    final position = await _loadPosition(
      db,
      workspace,
      PublicId.parse(row.read<String>('investment_account_id')),
      PublicId.parse(row.read<String>('instrument_id')),
    );
    facts.addAll(position.splits);
  }
  facts.sort((a, b) {
    final date = a.preview.effectiveOn.compareTo(b.preview.effectiveOn);
    return date == 0 ? a.preview.id.value.compareTo(b.preview.id.value) : date;
  });
  return List.unmodifiable(facts);
}

Future<void> validateInvestmentSplitFacts(ProbeDatabase db) async {
  _requireSplitSchema(db);
  await validateInvestmentDividendFacts(db);
  final positions = await db
      .customSelect(
        'SELECT DISTINCT workspace,investment_account_id,instrument_id FROM investment_splits',
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
  final orphanLots = await db
      .customSelect(
        'SELECT l.split_id FROM investment_split_lots l '
        'LEFT JOIN investment_splits s ON s.workspace=l.workspace AND s.split_id=l.split_id '
        'WHERE s.split_id IS NULL LIMIT 1',
      )
      .get();
  final orphanAudits = await db
      .customSelect(
        "SELECT a.operation_id FROM audit a LEFT JOIN investment_splits s "
        "ON s.workspace=a.workspace AND s.operation_id=a.operation_id "
        "WHERE a.kind='investment.split-v1' AND s.split_id IS NULL LIMIT 1",
      )
      .get();
  if (orphanLots.isNotEmpty || orphanAudits.isNotEmpty) {
    throw const FormatException('Orphan investment split fact');
  }
}

void _requireSplitSchema(ProbeDatabase db) {
  if (!db.investmentSplitsAware) {
    throw const FormatException('Investment split schema unavailable');
  }
}

bool _matchesSplitIdentity(StockSplitPreview split, InvestmentBuyPreview buy) =>
    split.broker.id == buy.broker.id &&
    split.broker.name == buy.broker.name &&
    split.account.id == buy.account.id &&
    split.account.name == buy.account.name &&
    split.account.expectedVersion == buy.account.expectedVersion &&
    split.account.fundingCashAccountId == buy.account.fundingCashAccountId &&
    split.instrument.id == buy.instrument.id &&
    split.instrument.kind == buy.instrument.kind &&
    split.instrument.marketCode == buy.instrument.marketCode &&
    split.instrument.symbol == buy.instrument.symbol &&
    split.instrument.name == buy.instrument.name &&
    split.instrument.tradingCurrency == buy.instrument.tradingCurrency;

BigInt _splitUnits(ShareQuantity quantity) =>
    quantity.coefficient * BigInt.from(10).pow(12 - quantity.scale);

Future<InvestmentSplitFact> _applySplitRow(
  ProbeDatabase db,
  QueryRow row,
  InvestmentBuyPreview identity,
  Map<PublicId, InvestmentHoldingLot> lots,
) async {
  final payload = row.read<String>('payload');
  final preview = const StockSplitPreviewCodec().decode(payload);
  final ws = preview.operation.workspace.toString();
  if (!_matchesSplitIdentity(preview, identity) ||
      row.read<String>('workspace') != ws ||
      row.read<String>('split_id') != preview.id.value ||
      row.read<String>('operation_id') !=
          preview.operation.operation.toString() ||
      row.read<String>('investment_account_id') != preview.account.id.value ||
      row.read<String>('instrument_id') != preview.instrument.id.value ||
      row.read<String>('broker_id') != preview.broker.id.value ||
      row.read<String>('effective_on') != preview.effectiveOn.toString()) {
    throw const FormatException('Investment split payload mismatch');
  }
  preview.verifyCurrentLots(lots.values.toList());
  final rows = await db
      .customSelect(
        'SELECT * FROM investment_split_lots WHERE workspace=? AND split_id=? ORDER BY ordinal',
        variables: [Variable(ws), Variable(preview.id.value)],
      )
      .get();
  if (rows.length != preview.lots.length) {
    throw const FormatException('Investment split lot count mismatch');
  }
  for (var index = 0; index < rows.length; index++) {
    final actual = rows[index];
    final expected = preview.lots[index];
    if (actual.read<String>('lot_id') != expected.before.id.value ||
        actual.read<int>('ordinal') != index ||
        actual.read<String>('before_quantity_units') !=
            _splitUnits(expected.before.remainingQuantity).toString() ||
        actual.read<String>('after_quantity_units') !=
            _splitUnits(expected.afterQuantity).toString() ||
        actual.read<int>('unchanged_cost') !=
            expected.before.remainingCost.minorUnits.toInt() ||
        actual.read<int>('prior_version') != expected.before.expectedVersion) {
      throw const FormatException('Investment split lot mismatch');
    }
  }
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
  if (receipt == null ||
      receipt.read<String>('input') !=
          jsonEncode(['investment-split-v1', preview.id.value, payload]) ||
      receipt.read<String>('result_id') != preview.id.value ||
      receipt.read<String?>('entity_id') != preview.id.value ||
      receipt.read<String?>('kind') != 'investment.split-v1') {
    throw const FormatException('Investment split receipt mismatch');
  }
  for (final change in preview.lots) {
    lots[change.before.id] = InvestmentHoldingLot(
      id: change.before.id,
      investmentAccountId: change.before.investmentAccountId,
      instrumentId: change.before.instrumentId,
      acquiredOn: change.before.acquiredOn,
      remainingQuantity: change.afterQuantity,
      remainingCost: change.before.remainingCost,
      expectedVersion: change.before.expectedVersion + 1,
    );
  }
  return InvestmentSplitFact(preview, row.read<int>('sequence'));
}
