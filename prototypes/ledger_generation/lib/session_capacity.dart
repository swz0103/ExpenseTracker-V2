part of 'ledger_store.dart';

// These bounds are for the current bounded session, not the final M3 capacity.
// Each accepted command adds known rows; updates cannot evade encoded byte caps.
const _rowByteLimits = <String, int>{
  'accounts': 4096,
  'events': 512,
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
};
Map<String, int> _tableLimits(
  bool categories,
  bool references,
  bool tags,
  bool merchants,
) => {
  'accounts': LedgerSession.maxAccounts,
  'events': LedgerSession.maxEvents,
  'legs': LedgerSession.maxEvents,
  'openings': LedgerSession.maxAccounts,
  'allocations': references ? SnapshotCodec.maxRows : 0,
  'receipts':
      LedgerSession.maxEvents +
      (categories ? LedgerSession.maxCategoryChanges : 0) +
      (tags ? LedgerSession.maxTagChanges : 0) +
      (merchants ? LedgerSession.maxMerchantChanges : 0),
  'audit':
      LedgerSession.maxEvents +
      (categories ? LedgerSession.maxCategoryChanges : 0) +
      (tags ? LedgerSession.maxTagChanges : 0) +
      (merchants ? LedgerSession.maxMerchantChanges : 0),
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
  return input is List && input.isNotEmpty && input.first == 'create-v1';
}

void _checkRowBytes(String table, Map row) {
  final limit =
      table == 'receipts' &&
          (_accountReceipt(row) ||
              [
                'tagged-post-v1',
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
}) {
  tagsAware = tagsAware || merchantsAware;
  categoryReferences = categoryReferences || tagsAware;
  categoryAware = categoryAware || categoryReferences;
  final codec = SnapshotCodec(
    generationAware: true,
    categoryAware: categoryAware,
    categoryReferences: categoryReferences,
    tagsAware: tagsAware,
    merchantsAware: merchantsAware,
  );
  final canonical = codec.canonicalize(bytes);
  final tables = (jsonDecode(utf8.decode(canonical)) as Map)['tables'] as Map;
  final limits = _tableLimits(
    categoryAware,
    categoryReferences,
    tagsAware,
    merchantsAware,
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
      (merchantsAware ? (tables['merchant_changes'] as List).length : 0);
  if (events.any(
        (row) => !['opening', 'income', 'expense'].contains(row['kind']),
      ) ||
      (tables['legs'] as List).length != events.length ||
      receipts.length != events.length + changes ||
      (tables['audit'] as List).length != receipts.length ||
      receipts.where((row) => _accountReceipt(row as Map)).length >
          LedgerSession.maxAccounts) {
    throw PreviewCapacity();
  }
  return canonical;
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
