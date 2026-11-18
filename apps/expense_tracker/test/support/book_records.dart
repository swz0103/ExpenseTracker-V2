import 'dart:convert';

import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/ledger/persistence/codec/record_json.dart';

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
