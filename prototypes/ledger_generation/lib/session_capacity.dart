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
  'card_installment_plans': 4096,
  'investment_brokers': 4096,
  'investment_accounts': 4096,
  'investment_instruments': 4096,
  'investment_buys': 8192,
  'investment_lots': 4096,
  'investment_sales': 1024 * 1024,
  'investment_sale_allocations': 512,
  'investment_dividends': 8192,
  'investment_splits': 1024 * 1024,
  'investment_split_lots': 512,
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
  bool installments,
  bool investments,
  bool investmentSales,
  bool investmentDividends,
  bool investmentSplits,
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
  if (installments) 'card_installment_plans': LedgerSession.maxEvents,
  if (investments) 'investment_brokers': LedgerSession.maxAccounts,
  if (investments) 'investment_accounts': LedgerSession.maxAccounts,
  if (investments) 'investment_instruments': LedgerSession.maxEvents,
  if (investments) 'investment_buys': LedgerSession.maxEvents,
  if (investments) 'investment_lots': LedgerSession.maxEvents,
  if (investmentSales) 'investment_sales': LedgerSession.maxEvents,
  if (investmentSales) 'investment_sale_allocations': SnapshotCodec.maxRows,
  if (investmentDividends) 'investment_dividends': LedgerSession.maxEvents,
  if (investmentSplits) 'investment_splits': LedgerSession.maxEvents,
  if (investmentSplits) 'investment_split_lots': SnapshotCodec.maxRows,
  'legs': LedgerSession.maxEvents * (transfers ? 3 : 1),
  'openings': LedgerSession.maxAccounts,
  'allocations': references ? SnapshotCodec.maxRows : 0,
  'receipts':
      LedgerSession.maxEvents +
      (categories ? LedgerSession.maxCategoryChanges : 0) +
      (tags ? LedgerSession.maxTagChanges : 0) +
      (merchants ? LedgerSession.maxMerchantChanges : 0) +
      (notes ? LedgerSession.maxNoteChanges : 0) +
      (tombstones ? LedgerSession.maxEvents : 0) +
      (investmentSplits ? LedgerSession.maxEvents : 0),
  'audit':
      LedgerSession.maxEvents +
      (categories ? LedgerSession.maxCategoryChanges : 0) +
      (tags ? LedgerSession.maxTagChanges : 0) +
      (merchants ? LedgerSession.maxMerchantChanges : 0) +
      (notes ? LedgerSession.maxNoteChanges : 0) +
      (tombstones ? LedgerSession.maxEvents : 0) +
      (investmentSplits ? LedgerSession.maxEvents : 0),
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

bool _accountMutationReceipt(Map row) {
  final input = jsonDecode(row['input'] as String);
  return input is List &&
      input.isNotEmpty &&
      {
        'archive-v1',
        'account-rename-v1',
        'account-net-worth-v1',
        'account-reactivate-v1',
        'account-close-v1',
      }.contains(input.first);
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
                _accountMutationReceipt(row) ||
                [
                  'posting-v2', // Allocations need the same bound with or without tags.
                  'tagged-post-v1',
                  'fx-posting-v1',
                  'refund-posting-v1',
                  'reversal-posting-v1',
                  'merchant-post-v1',
                  'investment-buy-v1',
                  'investment-sell-v1',
                  'investment-dividend-v1',
                  'investment-split-v1',
                ].contains((jsonDecode(row['input'] as String) as List).first))
      ? input?.first == 'investment-sell-v1'
            ? 1024 * 1024
            : input?.first == 'investment-split-v1'
            ? 1024 * 1024
            : input?.first == 'investment-dividend-v1'
            ? 8192
            : 4096
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
  bool installmentsAware = false,
  bool investmentsAware = false,
  bool investmentSalesAware = false,
  bool investmentDividendsAware = false,
  bool investmentSplitsAware = false,
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
    installmentsAware: installmentsAware,
    investmentsAware: investmentsAware,
    investmentSalesAware: investmentSalesAware,
    investmentDividendsAware: investmentDividendsAware,
    investmentSplitsAware: investmentSplitsAware,
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
    installmentsAware,
    investmentsAware,
    investmentSalesAware,
    investmentDividendsAware,
    investmentSplitsAware,
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
  final accountChanges = receipts
      .where((row) => _accountMutationReceipt(row as Map))
      .length;
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
          if (investmentsAware) 'investmentBuy',
          if (investmentSalesAware) 'investmentSell',
          if (investmentDividendsAware) 'investmentDividend',
        ].contains(row['kind']),
      ) ||
      (!_validLegCounts(events, tables['legs'] as List, transfersAware)) ||
      receipts.length !=
          events.length +
              changes +
              accountChanges +
              (investmentSplitsAware
                  ? (tables['investment_splits'] as List).length
                  : 0) ||
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

void _requireInspectedCapacity(
  SnapshotCapacityInspection inspection,
  Map<String, int> limits,
) {
  _requirePortableUsage((rows: inspection.rows, bytes: inspection.bytes));
  if (inspection.tableRows.length != limits.length) throw PreviewCapacity();
  for (final entry in inspection.tableRows.entries) {
    final limit = limits[entry.key];
    if (limit == null || entry.value > limit) throw PreviewCapacity();
  }
}

extension _SessionRowCapacity on LedgerSession {
  static const _projectionFormat = 1;
  static const _projectionColumns = <String>[
    'singleton',
    'format_version',
    'schema_version',
    'generation',
    'rows',
    'bytes',
    'table_counts',
    'checksum',
  ];

  Map<String, int> _capacityLimits() => _tableLimits(
    _db.categoryAware,
    _db.categoryReferences,
    _db.tagsAware,
    _db.merchantsAware,
    _db.transfersAware,
    _db.fxTransfersAware,
    _db.refundsAware,
    _db.reversalsAware,
    _db.notesAware,
    _db.correctionsAware,
    _db.tombstonesAware,
    _db.budgetsAware,
    _db.recurringAware,
    _db.creditCardsAware,
    _db.cardStatementsAware,
    _db.cardAuthorizationsAware,
    _db.installmentsAware,
    _db.investmentsAware,
    _db.investmentSalesAware,
    _db.investmentDividendsAware,
    _db.investmentSplitsAware,
  );

  String _capacityChecksum(
    String generation,
    int rows,
    int bytes,
    String tableCounts,
  ) => sha256
      .convert(
        utf8.encode(
          '$_projectionFormat|${_db.schemaVersion}|$generation|$rows|$bytes|$tableCounts',
        ),
      )
      .toString();

  Future<String> _capacityGeneration() async {
    final cached = _capacityGenerationValue;
    if (cached != null) return cached;
    final rows = await _db
        .customSelect('SELECT generation FROM storage_identity')
        .get();
    if (rows.length != 1) throw PreviewCapacity();
    return _capacityGenerationValue = rows.single.read<String>('generation');
  }

  Future<Map<String, int>> _currentTableCounts(Map<String, int> limits) async {
    final counts = <String, int>{};
    for (final entry in limits.entries) {
      final count = await _count(entry.key);
      if (count < 0 || count > entry.value) throw PreviewCapacity();
      counts[entry.key] = count;
    }
    return counts;
  }

  Future<({int rows, int bytes, Map<String, int> tableRows})?>
  _readCapacityProjection() async {
    final shape = await _db
        .customSelect('PRAGMA table_xinfo(capacity_projection)')
        .get();
    if (shape.length != _projectionColumns.length ||
        shape.asMap().entries.any(
          (entry) =>
              entry.value.read<String>('name') != _projectionColumns[entry.key],
        )) {
      throw PreviewCapacity();
    }
    final records = await _db
        .customSelect('SELECT * FROM capacity_projection')
        .get();
    if (records.isEmpty) return null;
    if (records.length != 1) throw PreviewCapacity();
    final row = records.single;
    final format = row.read<int>('format_version');
    final schema = row.read<int>('schema_version');
    final generation = row.read<String>('generation');
    final rows = row.read<int>('rows');
    final bytes = row.read<int>('bytes');
    final encodedCounts = row.read<String>('table_counts');
    final checksum = row.read<String>('checksum');
    if (row.read<int>('singleton') != 1 ||
        format != _projectionFormat ||
        schema != _db.schemaVersion ||
        generation != await _capacityGeneration() ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(checksum) ||
        checksum != _capacityChecksum(generation, rows, bytes, encodedCounts)) {
      return null;
    }
    Object? decoded;
    try {
      decoded = jsonDecode(encodedCounts);
    } catch (_) {
      return null;
    }
    final limits = _capacityLimits();
    if (decoded is! Map || decoded.length != limits.length) return null;
    final saved = <String, int>{};
    for (final entry in decoded.entries) {
      if (entry.key is! String || entry.value is! int) return null;
      saved[entry.key as String] = entry.value as int;
    }
    if (saved.keys.any((key) => !limits.containsKey(key)) ||
        saved.values.any((value) => value < 0) ||
        saved.values.fold<int>(0, (sum, value) => sum + value) != rows) {
      return null;
    }
    final actual = await _currentTableCounts(limits);
    if (jsonEncode(actual) != encodedCounts) return null;
    final usage = (rows: rows, bytes: bytes);
    _requirePortableUsage(usage);
    return (rows: rows, bytes: bytes, tableRows: saved);
  }

  Future<void> _persistCapacityProjection(({int rows, int bytes}) usage) async {
    _requirePortableUsage(usage);
    final limits = _capacityLimits();
    final counts = _capacityTableRows;
    if (counts == null ||
        counts.length != limits.length ||
        counts.keys.any((key) => !limits.containsKey(key)) ||
        counts.entries.any(
          (entry) => entry.value < 0 || entry.value > limits[entry.key]!,
        )) {
      throw PreviewCapacity();
    }
    if (counts.values.fold<int>(0, (sum, value) => sum + value) != usage.rows) {
      throw PreviewCapacity();
    }
    final encodedCounts = jsonEncode(counts);
    final generation = await _capacityGeneration();
    final checksum = _capacityChecksum(
      generation,
      usage.rows,
      usage.bytes,
      encodedCounts,
    );
    await _db.customStatement(
      'INSERT INTO capacity_projection '
      '(singleton,format_version,schema_version,generation,rows,bytes,table_counts,checksum) '
      'VALUES(1,?,?,?,?,?,?,?) '
      'ON CONFLICT(singleton) DO UPDATE SET '
      'format_version=excluded.format_version, '
      'schema_version=excluded.schema_version, generation=excluded.generation, '
      'rows=excluded.rows, '
      'bytes=excluded.bytes, table_counts=excluded.table_counts, '
      'checksum=excluded.checksum',
      [
        _projectionFormat,
        _db.schemaVersion,
        generation,
        usage.rows,
        usage.bytes,
        encodedCounts,
        checksum,
      ],
    );
  }

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
      final counts = _capacityTableRows!;
      final count = (counts[table] ?? (throw PreviewCapacity())) + delta;
      final limit = _capacityLimits()[table];
      if (limit == null || count < 0 || count > limit) {
        throw PreviewCapacity();
      }
      counts[table] = count;
      _capacityUsage = next;
      _capacityProjectionDirty = true;
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
