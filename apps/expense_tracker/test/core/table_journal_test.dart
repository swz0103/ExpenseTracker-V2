import 'dart:convert';
import 'dart:io';

import 'package:core/app_core.dart';
import 'package:core/foundation_values.dart';
import 'package:expense_tracker/src/core/ledger/table_journal.dart';
import 'package:expense_tracker/src/app/demo/seed.dart';
import 'package:expense_tracker/src/core/ledger/journal.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/ledger/record_json.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:storage/storage.dart';

/// The screens' ledger on the real encrypted store: every change is kept
/// as the records it touched, and comes back after closing and reopening.
void main() {
  late Directory directory;
  late File file;
  final key = StorageKey.random();
  var now = DateTime.utc(2026, 10, 4, 4);
  RowStore? store;

  Clock clock() => FixedClock(UtcInstant(now));

  Future<Ledger> reopen([Ledger? ledger]) async {
    if (ledger != null) {
      await ledger.settled;
      expect(ledger.problem.value, isNull);
    }
    store?.close();
    final opened = RowStore.open(file, key);
    store = opened;
    return TableJournal(opened, clock: clock()).load();
  }

  setUp(() {
    directory = Directory.systemTemp.createTempSync('journal-');
    file = File('${directory.path}/ledger.db');
    now = DateTime.utc(2026, 10, 4, 4);
  });

  tearDown(() {
    store?.close();
    store = null;
    directory.deleteSync(recursive: true);
  });

  /// Every record as its JSON, for comparing two ledgers.
  Map<String, Object?> recordsOf(Ledger l) => {
    'accounts': [for (final a in l.accounts) accountToJson(a)],
    'categories': [for (final c in l.categories) categoryToJson(c)],
    'entries': [for (final e in l.entries) entryToJson(e)],
    'budgets': [for (final b in l.budgets) budgetToJson(b)],
    'recurring': [for (final r in l.recurring) recurringToJson(r)],
  };

  test('a new ledger starts with categories and two accounts', () async {
    final ledger = await reopen();
    expect(ledger.categories, hasLength(9));
    expect(ledger.categoriesFor(income: true), hasLength(3));
    expect(
      [for (final a in ledger.accounts) a.kind],
      [AccountKind.cash, AccountKind.bank],
    );
    // Opened again, nothing is added twice.
    final again = await reopen();
    expect(recordsOf(again), recordsOf(ledger));
  });

  test('every kind of record comes back in order, with its sums', () async {
    final demo = demoLedger();
    final opened = RowStore.open(file, key);
    store = opened;
    await TableJournal(opened).keep(
      Batch(
        accounts: demo.accounts,
        categories: demo.categories,
        entries: demo.entries,
        budgets: demo.budgets,
        recurring: demo.recurring,
      ),
    );
    final ledger = await reopen();
    expect(jsonEncode(recordsOf(ledger)), jsonEncode(recordsOf(demo)));
    for (final a in demo.accounts) {
      expect(ledger.balance(a.id), demo.balance(a.id), reason: a.name);
    }
    final card = ledger.account('card');
    expect(ledger.statementDue(card), demo.statementDue(card));
    expect(ledger.expense(2026, 10), demo.expense(2026, 10));
    expect(
      ledger.instalmentsOn(card),
      hasLength(demo.instalmentsOn(card).length),
    );
  });

  test('changes through the ledger are kept as they are shown', () async {
    var ledger = await reopen();
    final cash = ledger.accounts.first;
    final card = Account(
      ledger.newId(),
      '卡',
      AccountKind.card,
      0,
      closingDay: 25,
      dueDay: 10,
    );
    ledger
      ..addAccount(card)
      ..add(
        Entry(
          id: ledger.newId(),
          date: DateTime.utc(2026, 10, 2),
          type: EntryType.expense,
          amount: 120,
          account: cash.id,
          category: '飲食日常',
          merchant: '全聯',
          tags: const ['家用'],
        ),
      )
      ..setBudget('飲食日常', 8000, carry: true)
      ..saveRecurring(
        Recurring(
          id: ledger.newId(),
          name: '房租',
          amount: 12000,
          day: 5,
          account: cash.id,
          category: '居家生活',
        ),
      );
    ledger = await reopen(ledger);
    final lunch = ledger.entries.single;
    expect(ledger.balance(cash.id), -120);
    expect(ledger.budgetFor('飲食日常').carry, isTrue);
    expect(ledger.recurring.single.name, '房租');

    // A renamed category reaches its entries and budget; a renamed tag
    // and merchant reach their entries.
    ledger
      ..updateCategory('飲食日常', ledger.category('飲食日常').copyWith(name: '吃'))
      ..renameTag('家用', '家')
      ..renameMerchant('全聯', '全聯福利中心')
      ..moveClose(
        card.id,
        DateTime.utc(2026, 10, 25),
        DateTime.utc(2026, 10, 23),
      )
      ..updateAccount(
        ledger.account(card.id).copyWith(closingDay: 5, dueDay: 20),
      )
      ..setReceipt(lunch.id, 'lunch.etr');
    ledger = await reopen(ledger);
    final renamed = ledger.entries.single;
    expect((renamed.category, renamed.merchant), ('吃', '全聯福利中心'));
    expect(renamed.tags, ['家']);
    expect(ledger.budgets.single.category, '吃');
    expect(ledger.categories.where((c) => c.name == '飲食日常'), isEmpty);
    final moved = ledger.account(card.id);
    expect(moved.closes, {
      DateTime.utc(2026, 10, 25): DateTime.utc(2026, 10, 23),
    });
    expect((moved.closingDay, moved.history.single.closingDay), (5, 25));
    expect(ledger.receiptOf(lunch.id), 'lunch.etr');

    // Deleted, then restored from the trash: the same entry, its photo
    // still with it.
    ledger.remove(lunch.id);
    ledger = await reopen(ledger);
    expect(ledger.entries, isEmpty);
    expect(ledger.trash.single.entry.id, lunch.id);
    ledger.restoreTrashed(ledger.trash.single);
    ledger = await reopen(ledger);
    expect(ledger.entries.single.id, lunch.id);
    expect(ledger.trash, isEmpty);
    expect(ledger.receiptOf(lunch.id), 'lunch.etr');

    ledger
      ..removeBudget('吃')
      ..removeRecurring(ledger.recurring.single.id)
      ..mergeCategory('吃', '其他支出');
    ledger = await reopen(ledger);
    expect(ledger.budgets, isEmpty);
    expect(ledger.recurring, isEmpty);
    expect(ledger.entries.single.category, '其他支出');
  });

  test('a deleted entry is kept 30 days', () async {
    var ledger = await reopen();
    final cash = ledger.accounts.first;
    final entry = Entry(
      id: ledger.newId(),
      date: DateTime.utc(2026, 10, 2),
      type: EntryType.expense,
      amount: 50,
      account: cash.id,
      category: '飲食日常',
    );
    ledger.add(entry);
    ledger.remove(entry.id);
    ledger = await reopen(ledger);
    expect(ledger.trash, hasLength(1));
    now = DateTime.utc(2026, 11, 2, 4);
    ledger = await reopen();
    expect(ledger.trash, hasLength(1));
    now = DateTime.utc(2026, 11, 4, 4);
    ledger = await reopen();
    expect(ledger.trash, isEmpty);
    expect(store!.rows(shelf: Shelf.trash.name), isEmpty);
  });

  test('a change that cannot be kept is reported and read back', () async {
    final ledger = await reopen();
    store!.close();
    ledger.addCategory(const Category('寵物', 'pet', Color(0xFF123456)));
    await ledger.settled;
    expect(ledger.problem.value, isA<JournalFailure>());
  });

  test('a record the app cannot read is told apart', () {
    final demo = demoLedger();
    final entry = jsonEncode(entryToJson(demo.entries.first));
    TableJournal.check('entry', 'e', entry);
    TableJournal.check('receipt', 'e', 'lunch.etr');
    for (final (shelf, body) in [
      ('entry', '{"id":"x"}'),
      ('entry', 'not json'),
      ('receipt', '../escape'),
      ('castle', '{}'),
      ('market', '{"prices":{"2330":"high"}}'),
    ]) {
      expect(
        () => TableJournal.check(shelf, 'x', body),
        throwsA(anyOf(isA<FormatException>(), isA<TypeError>())),
        reason: '$shelf $body',
      );
    }
  });
}
