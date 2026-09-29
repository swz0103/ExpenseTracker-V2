part of 'ledger_store.dart';

// These bounds are for the current bounded session, not the final M3 capacity.
// Each accepted command adds known rows; updates cannot evade encoded byte caps.
const _rowByteLimits = <String, int>{
  'accounts': 4096,
  'events': 512,
  'event_fx': 1024,
  'event_refunds': 512,
  'event_reversals': 2048,
  'event_note_revisions': 8192,
  'event_corrections': 512,
  'event_tombstones': 512,
  'legs': 512,
  'openings': 512,
  'allocations': 512,
  'receipts': 1024,
  'audit': 512,
  'categories': 1024,
  'category_changes': 1024,
  'tags': 1024,
  'tag_changes': 1024,
  'event_tags': 512,
  'merchants': 8192,
  'merchant_changes': 8192,
  'event_merchants': 512,
  'budget_revisions': 8192,
  'recurring_revisions': 8192,
  'recurring_occurrences': 1024,
  'card_revisions': 8192,
  'card_posted_charges': 512,
  'card_statements': 1024,
  'card_payments': 512,
  'card_payment_allocations': 512,
  'card_authorizations': 512,
  'card_authorization_resolutions': 512,
};
Map<String, int> _tableLimits(
  bool categories,
  bool references,
  bool tags,
  bool merchants,
  bool transfers,
  bool fxTransfers,
  bool refunds,
  bool reversals,
  bool notes,
  bool corrections,
  bool tombstones,
  bool budgets,
  bool recurring,
  bool creditCards,
  bool cardStatements,
  bool cardAuthorizations,
) => {
  'accounts': LedgerSession.maxAccounts,
  'events': LedgerSession.maxEvents,
  if (fxTransfers) 'event_fx': LedgerSession.maxEvents,
  if (refunds) 'event_refunds': LedgerSession.maxEvents,
  if (reversals) 'event_reversals': LedgerSession.maxEvents,
  if (notes) 'event_note_revisions': LedgerSession.maxNoteChanges,
  if (corrections) 'event_corrections': LedgerSession.maxEvents ~/ 2,
  if (tombstones) 'event_tombstones': LedgerSession.maxEvents,
  if (budgets) 'budget_revisions': LedgerSession.maxBudgetChanges,
  if (recurring) 'recurring_revisions': LedgerSession.maxRecurringChanges,
  if (recurring) 'recurring_occurrences': LedgerSession.maxEvents,
  if (creditCards) 'card_revisions': LedgerSession.maxCardChanges,
  if (cardStatements) 'card_posted_charges': LedgerSession.maxEvents,
  if (cardStatements) 'card_statements': LedgerSession.maxEvents,
  if (cardStatements) 'card_payments': LedgerSession.maxEvents,
  if (cardStatements) 'card_payment_allocations': SnapshotCodec.maxRows,
  if (cardAuthorizations) 'card_authorizations': LedgerSession.maxEvents,
  if (cardAuthorizations)
    'card_authorization_resolutions': LedgerSession.maxEvents,
  'legs': LedgerSession.maxEvents * (transfers ? 3 : 1),
  'openings': LedgerSession.maxAccounts,
  'allocations': references ? SnapshotCodec.maxRows : 0,
  'receipts':
      LedgerSession.maxEvents +
      (categories ? LedgerSession.maxCategoryChanges : 0) +
      (tags ? LedgerSession.maxTagChanges : 0) +
      (merchants ? LedgerSession.maxMerchantChanges : 0) +
      (notes ? LedgerSession.maxNoteChanges : 0) +
      (tombstones ? LedgerSession.maxEvents : 0),
  'audit':
      LedgerSession.maxEvents +
      (categories ? LedgerSession.maxCategoryChanges : 0) +
      (tags ? LedgerSession.maxTagChanges : 0) +
      (merchants ? LedgerSession.maxMerchantChanges : 0) +
      (notes ? LedgerSession.maxNoteChanges : 0) +
      (tombstones ? LedgerSession.maxEvents : 0),
  if (merchants) 'merchants': LedgerSession.maxMerchants,
  if (merchants) 'merchant_changes': LedgerSession.maxMerchantChanges,
  if (merchants) 'event_merchants': LedgerSession.maxEvents,
  if (tags) 'tags': LedgerSession.maxTags,
  if (tags) 'tag_changes': LedgerSession.maxTagChanges,
  if (tags) 'event_tags': SnapshotCodec.maxRows,
  if (categories) 'categories': LedgerSession.maxCategories,
  if (categories) 'category_changes': LedgerSession.maxCategoryChanges,
};

bool _accountReceipt(Map row) {
  final input = jsonDecode(row['input'] as String);
  return input is List &&
      input.isNotEmpty &&
      (input.first == 'create-v1' || input.first == 'card-create-v1');
}

bool _reversalReceipt(Map row) {
  var input = jsonDecode(row['input'] as String);
  if (input is List &&
      input.length == 6 &&
      input.first == 'correction-event-v1') {
    input = input[5];
  }
  // Only known outer attribution wrappers may carry a reversal receipt.
  for (final wrapper in ['merchant-post-v1', 'tagged-post-v1']) {
    if (input is List && input.length == 3 && input.first == wrapper)
      input = input[1];
  }
  return input is List &&
      input.length == 5 &&
      input.first == 'reversal-posting-v1';
}

void _checkRowBytes(String table, Map row) {
  final input = table == 'receipts'
      ? jsonDecode(row['input'] as String) as List
      : null;
  final limit =
      input != null &&
          (input.first == 'correction-event-v1' ||
              input.first == 'tombstone-v1')
      ? 12288
      : table == 'receipts' &&
            (_reversalReceipt(row) ||
                (jsonDecode(row['input'] as String) as List).first == 'note-v1')
      ? 8192
      : table == 'receipts' &&
            (_accountReceipt(row) ||
                [
                  'posting-v2', // Allocations need the same bound with or without tags.
                  'tagged-post-v1',
                  'fx-posting-v1',
                  'refund-posting-v1',
                  'reversal-posting-v1',
                  'merchant-post-v1',
                ].contains((jsonDecode(row['input'] as String) as List).first))
      ? 4096
      : _rowByteLimits[table];
  if (limit == null || utf8.encode(jsonEncode(row)).length > limit)
    throw PreviewCapacity();
}

/// Capacity/representable-subset admission, not a substitute for full restore
/// validation. Returns the canonical bytes so import callers need not recode.
/// Larger valid stores remain readable/exportable but cannot gain new writes
/// through this bounded session; existing operations can still replay.
List<int> validateSessionCapacity(
  List<int> bytes, {
  bool categoryAware = false,
  bool categoryReferences = false,
  bool tagsAware = false,
  bool merchantsAware = false,
  bool transfersAware = false,
  bool fxTransfersAware = false,
  bool refundsAware = false,
  bool reversalsAware = false,
  bool notesAware = false,
  bool correctionsAware = false,
  bool tombstonesAware = false,
  bool budgetsAware = false,
  bool recurringAware = false,
  bool creditCardsAware = false,
  bool cardStatementsAware = false,
  bool cardAuthorizationsAware = false,
}) {
  correctionsAware = correctionsAware || tombstonesAware;
  notesAware = notesAware || correctionsAware;
  reversalsAware = reversalsAware || notesAware;
  refundsAware = refundsAware || reversalsAware;
  fxTransfersAware = fxTransfersAware || refundsAware;
  transfersAware = transfersAware || fxTransfersAware;
  merchantsAware = merchantsAware || transfersAware;
  tagsAware = tagsAware || merchantsAware;
  categoryReferences = categoryReferences || tagsAware;
  categoryAware = categoryAware || categoryReferences;
  final codec = SnapshotCodec(
    generationAware: true,
    categoryAware: categoryAware,
    categoryReferences: categoryReferences,
    tagsAware: tagsAware,
    merchantsAware: merchantsAware,
    transfersAware: transfersAware,
    fxTransfersAware: fxTransfersAware,
    refundsAware: refundsAware,
    reversalsAware: reversalsAware,
    notesAware: notesAware,
    correctionsAware: correctionsAware,
    tombstonesAware: tombstonesAware,
    budgetsAware: budgetsAware,
    recurringAware: recurringAware,
    creditCardsAware: creditCardsAware,
    cardStatementsAware: cardStatementsAware,
    cardAuthorizationsAware: cardAuthorizationsAware,
  );
  final canonical = codec.canonicalize(bytes);
  final tables = (jsonDecode(utf8.decode(canonical)) as Map)['tables'] as Map;
  final limits = _tableLimits(
    categoryAware,
    categoryReferences,
    tagsAware,
    merchantsAware,
    transfersAware,
    fxTransfersAware,
    refundsAware,
    reversalsAware,
    notesAware,
    correctionsAware,
    tombstonesAware,
    budgetsAware,
    recurringAware,
    creditCardsAware,
    cardStatementsAware,
    cardAuthorizationsAware,
  );
  _requirePortableUsage(_snapshotUsage(canonical));
  if (tables.length != limits.length) throw PreviewCapacity();
  for (final entry in tables.entries) {
    final rows = entry.value as List;
    final countLimit = limits[entry.key];
    if (countLimit == null || rows.length > countLimit) throw PreviewCapacity();
    for (final row in rows) {
      _checkRowBytes(entry.key as String, row as Map);
    }
  }
  final events = tables['events'] as List;
  final receipts = tables['receipts'] as List;
  final changes =
      (categoryAware ? (tables['category_changes'] as List).length : 0) +
      (tagsAware ? (tables['tag_changes'] as List).length : 0) +
      (merchantsAware ? (tables['merchant_changes'] as List).length : 0) +
      (notesAware ? (tables['event_note_revisions'] as List).length : 0) +
      (tombstonesAware ? (tables['event_tombstones'] as List).length : 0);
  if (events.any(
        (row) => ![
          'opening',
          'income',
          'expense',
          if (transfersAware) 'transfer',
          if (refundsAware) 'refund',
          if (reversalsAware) 'reversal',
        ].contains(row['kind']),
      ) ||
      (!_validLegCounts(events, tables['legs'] as List, transfersAware)) ||
      receipts.length != events.length + changes ||
      (tables['audit'] as List).length != receipts.length ||
      receipts.where((row) => _accountReceipt(row as Map)).length >
          LedgerSession.maxAccounts) {
    throw PreviewCapacity();
  }
  return canonical;
}

bool _validLegCounts(List events, List legs, bool transfers) {
  final counts = <(String, String), int>{};
  for (final row in legs) {
    final key = (row['workspace'] as String, row['event_id'] as String);
    counts[key] = (counts[key] ?? 0) + 1;
  }
  if (counts.length != events.length) return false;
  return events.every((row) {
    final count = counts[(row['workspace'] as String, row['id'] as String)];
    if (row['kind'] == 'reversal')
      return count != null && count >= 1 && count <= 3;
    return transfers && row['kind'] == 'transfer'
        ? count == 2 || count == 3
        : count == 1;
  });
}

// One conservative comma for every row, including each table's first row.
// Thus each accepted update has a cheap, exact delta with at most one spare byte per nonempty table.
({int rows, int bytes}) _snapshotUsage(List<int> canonical) {
  final tables = (jsonDecode(utf8.decode(canonical)) as Map)['tables'] as Map;
  var rows = 0, nonempty = 0;
  for (final value in tables.values) {
    rows += (value as List).length;
    if (value.isNotEmpty) nonempty++;
  }
  return (rows: rows, bytes: canonical.length + nonempty);
}

void _requirePortableUsage(({int rows, int bytes}) usage) {
  if (usage.rows > SnapshotCodec.maxRows ||
      usage.bytes > EnvelopeCodec.maxPayloadBytes ||
      usage.rows < 0 ||
      usage.bytes < 0)
    throw PreviewCapacity();
}

extension _SessionRowCapacity on LedgerSession {
  Future<void> _checkRows(
    String table,
    String predicate,
    List<String> values, {
    bool remove = false,
  }) async {
    final rows = await _db
        .customSelect(
          'SELECT * FROM $table WHERE $predicate',
          variables: values.map(Variable.withString).toList(),
        )
        .get();
    for (final row in rows) {
      final encoded = {
        for (final entry in row.data.entries)
          entry.key: entry.value is int ? entry.value.toString() : entry.value,
      };
      _checkRowBytes(table, encoded);
      final prior = _capacityUsage!;
      final delta = remove ? -1 : 1;
      final next = (
        rows: prior.rows + delta,
        bytes:
            prior.bytes + delta * (utf8.encode(jsonEncode(encoded)).length + 1),
      );
      _requirePortableUsage(next);
      _capacityUsage = next;
    }
  }

  Future<void> _checkOperationRows(OperationKey operation) async {
    final values = [
      operation.workspace.toString(),
      operation.operation.toString(),
    ];
    await _checkRows('receipts', 'workspace=? AND operation_id=?', values);
    await _checkRows('audit', 'workspace=? AND operation_id=?', values);
  }

  Future<void> _checkFinancialRows(Posting posting, {Account? account}) async {
    final ws = posting.operation.workspace.toString();
    if (account != null) {
      await _checkRows('accounts', 'workspace=? AND id=?', [
        ws,
        account.id.value,
      ]);
      await _checkRows('openings', 'workspace=? AND account_id=?', [
        ws,
        account.id.value,
      ]);
    }
    if (posting.reversalOf != null) {
      await _checkRows('event_reversals', 'workspace=? AND event_id=?', [
        ws,
        posting.id.value,
      ]);
    }
    if (posting.refundOf != null) {
      await _checkRows('event_refunds', 'workspace=? AND event_id=?', [
        ws,
        posting.id.value,
      ]);
    }
    if (posting.conversion != null) {
      await _checkRows('event_fx', 'workspace=? AND event_id=?', [
        ws,
        posting.id.value,
      ]);
    }
    await _checkRows('events', 'workspace=? AND id=?', [ws, posting.id.value]);
    await _checkRows('legs', 'workspace=? AND event_id=?', [
      ws,
      posting.id.value,
    ]);
    await _checkRows('allocations', 'workspace=? AND event_id=?', [
      ws,
      posting.id.value,
    ]);
    await _checkOperationRows(posting.operation);
  }
}
