import 'dart:convert';

import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/ledger/persistence/codec/record_json.dart';
import 'package:expense_tracker/src/core/ledger/persistence/record_version.dart';
import 'package:expense_tracker/src/core/ledger/persistence/write_batch.dart';

/// The tabs a form can be put aside on, as drafts are kept by.
const draftTabs = ['expense', 'income', 'transfer'];

/// Every record a ledger holds, as text, each kind sorted so that only
/// what is kept is compared, not where it stands; and the order each kind
/// is shown in, by id.
Map<String, List<String>> bookRecords(Ledger l) {
  List<String> sorted(Iterable<String> rows) => rows.toList()..sort();
  return {
    'accounts': sorted(l.accounts.all.map((a) => jsonEncode(accountToJson(a)))),
    'categories': sorted(
      l.categories.all.map((c) => jsonEncode(categoryToJson(c))),
    ),
    'entries': sorted(l.entries.all.map((e) => jsonEncode(entryToJson(e)))),
    'budgets': sorted(l.budgets.all.map((b) => jsonEncode(budgetToJson(b)))),
    'recurring': sorted(
      l.recurring.all.map((r) => jsonEncode(recurringToJson(r))),
    ),
    'trash': sorted(l.trash.all.map((t) => jsonEncode(trashedToJson(t)))),
    'receipts': sorted(l.attachmentCommands.receiptFiles),
    'drafts': [for (final tab in draftTabs) '$tab ${l.drafts.of(tab)}'],
    'order of accounts': [for (final a in l.accounts.all) a.id],
    'order of categories': [for (final c in l.categories.all) c.name],
    'order of entries': [for (final e in l.entries.all) e.id],
    'order of trash': [for (final t in l.trash.all) t.entry.id],
  };
}

/// The key of [bookRecords] written beside them in a kept book's
/// records.json: the record version they were written at.
const recordVersionKey = 'record version';

/// The collection each kind of record [bookRecords] lists is kept in.
const _collections = {
  'accounts': Collection.account,
  'categories': Collection.category,
  'entries': Collection.entry,
  'budgets': Collection.budget,
  'recurring': Collection.recurring,
  'trash': Collection.trash,
};

/// [row] with its keys in order, so two records holding the same compare
/// equal whatever order they were written in.
String _canonical(Map<String, Object?> row) {
  Object? sort(Object? value) => switch (value) {
    final Map<String, Object?> map => {
      for (final key in map.keys.toList()..sort()) key: sort(map[key]),
    },
    final List<Object?> list => [for (final item in list) sort(item)],
    _ => value,
  };
  return jsonEncode(sort(row));
}

/// [records] with each record's keys in order, as [upgradeRecords] gives
/// them.
Map<String, List<String>> canonicalRecords(Map<String, List<String>> records) =>
    {
      for (final MapEntry(key: kind, value: rows) in records.entries)
        kind: _collections.containsKey(kind)
            ? ([
                for (final row in rows)
                  _canonical(jsonDecode(row) as Map<String, Object?>),
              ]..sort())
            : rows,
    };

/// [written], the records an earlier version listed at record [version],
/// in this version's shape: each brought up by the app's own steps
/// ([upgradeRecord]) and nothing else, never read back through this
/// version's code, so a field this version drops or misreads still
/// shows. A record whose shape changed, with its upgrade step, compares
/// equal without the earlier version's file being touched.
Map<String, List<String>> upgradeRecords(
  Map<String, List<String>> written,
  int version, {
  Map<String, Object?> Function(String collection, Map<String, Object?> json)
      upgrade =
      upgradeRecord,
}) => {
  for (final MapEntry(key: kind, value: rows) in written.entries)
    if (kind != recordVersionKey)
      kind: switch (_collections[kind]) {
        null => rows,
        final collection => [
          for (final row in rows)
            _canonical(
              {
                ...upgrade(collection.name, {
                  ...jsonDecode(row) as Map<String, Object?>,
                  '_v': version,
                }),
              }..remove('_v'),
            ),
        ]..sort(),
      },
};
