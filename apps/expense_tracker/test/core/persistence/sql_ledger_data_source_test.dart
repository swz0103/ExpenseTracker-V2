import 'dart:convert';
import 'dart:io';

import 'package:core/app_core.dart';
import 'package:core/foundation_values.dart';
import 'package:expense_tracker/src/core/ledger/persistence/record_version.dart';
import 'package:expense_tracker/src/core/ledger/persistence/sql_ledger_data_source.dart';
import 'package:expense_tracker/src/app/demo/seed.dart';
import 'package:expense_tracker/src/core/ledger/persistence/ledger_data_source.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/ledger/persistence/codec/record_json.dart';
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
    return SqlLedgerDataSource(opened, clock: clock()).load();
  }

  setUp(() {
    directory = Directory.systemTemp.createTempSync('dataSource-');
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
    'accounts': [for (final a in l.accounts.all) accountToJson(a)],
    'categories': [for (final c in l.categories.all) categoryToJson(c)],
    'entries': [for (final e in l.entries.all) entryToJson(e)],
    'budgets': [for (final b in l.budgets.all) budgetToJson(b)],
    'recurring': [for (final r in l.recurring.all) recurringToJson(r)],
  };

  test('a new ledger starts with categories and two accounts', () async {
    final ledger = await reopen();
    expect(ledger.categories.all, hasLength(9));
    expect(ledger.categories.forEntries(income: true), hasLength(3));
    expect(
      [for (final a in ledger.accounts.all) a.kind],
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
    await SqlLedgerDataSource(opened).keep(
      WriteBatch(
        accounts: demo.accounts.all,
        categories: demo.categories.all,
        entries: demo.entries.all,
        budgets: demo.budgets.all,
        recurring: demo.recurring.all,
      ),
    );
    final ledger = await reopen();
    expect(jsonEncode(recordsOf(ledger)), jsonEncode(recordsOf(demo)));
    for (final a in demo.accounts.all) {
      expect(
        ledger.balanceService.balance(a.id),
        demo.balanceService.balance(a.id),
        reason: a.name,
      );
    }
    final card = ledger.account('card');
    expect(
      ledger.statementService.statementDue(card),
      demo.statementService.statementDue(card),
    );
    expect(
      ledger.reportService.expense(2026, 10),
      demo.reportService.expense(2026, 10),
    );
    expect(
      ledger.statementService.instalmentsOn(card),
      hasLength(demo.statementService.instalmentsOn(card).length),
    );
  });

  test('changes through the ledger are kept as they are shown', () async {
    var ledger = await reopen();
    final cash = ledger.accounts.all.first;
    final card = Account(
      ledger.newId(),
      '卡',
      AccountKind.card,
      0,
      closingDay: 25,
      dueDay: 10,
    );
    ledger
      ..accountCommands.addAccount(card)
      ..entryCommands.add(
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
      ..budgetCommands.setBudget('飲食日常', 8000, carry: true)
      ..recurringCommands.saveRecurring(
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
    final lunch = ledger.entries.all.single;
    expect(ledger.balanceService.balance(cash.id), -120);
    expect(ledger.budgets.forCategory('飲食日常').carry, isTrue);
    expect(ledger.recurring.all.single.name, '房租');

    // A renamed category reaches its entries and budget; a renamed tag
    // and merchant reach their entries.
    ledger
      ..categoryCommands.updateCategory(
        '飲食日常',
        ledger.category('飲食日常').copyWith(name: '吃'),
      )
      ..entryCommands.renameTag('家用', '家')
      ..entryCommands.renameMerchant('全聯', '全聯福利中心')
      ..accountCommands.moveClose(
        card.id,
        DateTime.utc(2026, 10, 25),
        DateTime.utc(2026, 10, 23),
      )
      ..accountCommands.updateAccount(
        ledger.account(card.id).copyWith(closingDay: 5, dueDay: 20),
      )
      ..attachmentCommands.setReceipt(lunch.id, 'lunch.etr');
    ledger = await reopen(ledger);
    final renamed = ledger.entries.all.single;
    expect((renamed.category, renamed.merchant), ('吃', '全聯福利中心'));
    expect(renamed.tags, ['家']);
    expect(ledger.budgets.all.single.category, '吃');
    expect(ledger.categories.all.where((c) => c.name == '飲食日常'), isEmpty);
    final moved = ledger.account(card.id);
    expect(moved.closes, {
      DateTime.utc(2026, 10, 25): DateTime.utc(2026, 10, 23),
    });
    expect((moved.closingDay, moved.history.single.closingDay), (5, 25));
    expect(ledger.receipts.of(lunch.id), 'lunch.etr');

    // Deleted, then restored from the trash: the same entry, its photo
    // still with it.
    ledger.entryCommands.remove(lunch.id);
    ledger = await reopen(ledger);
    expect(ledger.entries.all, isEmpty);
    expect(ledger.trash.all.single.entry.id, lunch.id);
    ledger.entryCommands.restoreTrashed(ledger.trash.all.single);
    ledger = await reopen(ledger);
    expect(ledger.entries.all.single.id, lunch.id);
    expect(ledger.trash.all, isEmpty);
    expect(ledger.receipts.of(lunch.id), 'lunch.etr');

    ledger
      ..budgetCommands.removeBudget('吃')
      ..recurringCommands.removeRecurring(ledger.recurring.all.single.id)
      ..categoryCommands.mergeCategory('吃', '其他支出');
    ledger = await reopen(ledger);
    expect(ledger.budgets.all, isEmpty);
    expect(ledger.recurring.all, isEmpty);
    expect(ledger.entries.all.single.category, '其他支出');
  });

  test('a deleted entry is kept 30 days', () async {
    var ledger = await reopen();
    final cash = ledger.accounts.all.first;
    final entry = Entry(
      id: ledger.newId(),
      date: DateTime.utc(2026, 10, 2),
      type: EntryType.expense,
      amount: 50,
      account: cash.id,
      category: '飲食日常',
    );
    ledger.entryCommands.add(entry);
    ledger.entryCommands.remove(entry.id);
    ledger = await reopen(ledger);
    expect(ledger.trash.all, hasLength(1));
    now = DateTime.utc(2026, 11, 2, 4);
    ledger = await reopen();
    expect(ledger.trash.all, hasLength(1));
    now = DateTime.utc(2026, 11, 4, 4);
    ledger = await reopen();
    expect(ledger.trash.all, isEmpty);
    expect(store!.rows(shelf: Collection.trash.name), isEmpty);
  });

  test('a change that cannot be kept is reported and read back', () async {
    final ledger = await reopen();
    store!.close();
    ledger.categoryCommands.addCategory(Category('寵物', 'pet', 0xFF123456));
    await ledger.settled;
    expect(ledger.problem.value, isA<DataSourceException>());
  });

  test('a record the app cannot read is told apart', () {
    final demo = demoLedger();
    final entry = jsonEncode(entryToJson(demo.entries.all.first));
    SqlLedgerDataSource.check('entry', 'e', entry);
    SqlLedgerDataSource.check('receipt', 'e', 'lunch.etr');
    for (final (collection, body) in [
      ('entry', '{"id":"x"}'),
      ('entry', 'not json'),
      ('receipt', '../escape'),
      ('castle', '{}'),
      ('market', '{"prices":{"2330":"high"}}'),
    ]) {
      expect(
        () => SqlLedgerDataSource.check(collection, 'x', body),
        throwsA(anyOf(isA<FormatException>(), isA<TypeError>())),
        reason: '$collection $body',
      );
    }
  });

  test('rows carry their version; deletions are noted and forgotten', () async {
    final ledger = await reopen();
    final bank = ledger.accounts.all.last;
    final entry = Entry(
      id: 'e1',
      date: DateTime.utc(2026, 10, 4),
      type: EntryType.expense,
      amount: 120,
      account: bank.id,
      category: ledger.categories.forEntries(income: false).first.name,
    );
    ledger.entryCommands.add(entry);
    await ledger.settled;
    final row = store!.rows(shelf: Collection.entry.name).single;
    final json = jsonDecode(row.body) as Map<String, Object?>;
    expect(json['_v'], recordVersion);
    expect(json['_at'], isA<int>());

    final removed = ledger.entryCommands.remove('e1')!;
    await ledger.settled;
    expect(store!.rows(shelf: 'gone').map((r) => r.id), ['entry/e1']);
    // Brought back: no longer gone.
    expect(ledger.entryCommands.restore(removed), isTrue);
    await ledger.settled;
    expect(store!.rows(shelf: 'gone'), isEmpty);
    // A backup carrying the note is accepted.
    SqlLedgerDataSource.check('gone', 'entry/e1', '{"at":1}');

    final again = await reopen(ledger);
    expect(again.entries.all.map((e) => e.id), contains('e1'));
  });

  test('a row from a newer app is refused, not misread', () {
    expect(
      () => upgradeRecord('entry', {'_v': recordVersion + 1}),
      throwsA(isA<FormatException>()),
    );
    // Rows from before versions were kept read as the first version.
    expect(upgradeRecord('entry', {'id': 'x'}), {'id': 'x'});
  });

  test('a large book is decoded off the screen thread', () async {
    final opened = RowStore.open(file, key);
    store = opened;
    final dataSource = SqlLedgerDataSource(opened, clock: clock());
    final first = await dataSource.load();
    final bank = first.accounts.all.last;
    final category = first.categories.forEntries(income: false).first.name;
    await dataSource.keep(
      WriteBatch(
        entries: [
          for (var i = 0; i < 2100; i++)
            Entry(
              id: 'e$i',
              date: DateTime.utc(2026, 1 + i % 9, 1 + i % 27),
              type: EntryType.expense,
              amount: 10 + i,
              account: bank.id,
              category: category,
            ),
        ],
      ),
    );
    final loaded = await reopen();
    expect(loaded.entries.all, hasLength(2100));
  });

  test('a form put aside outlasts the app and keeps its photo', () async {
    final ledger = await reopen();
    final revision = store!.revision;
    ledger.attachmentCommands.setDraft(
      'expense',
      '{"entry":{"id":"d"},"receipt":"1.etr"}',
    );
    await ledger.settled;
    // Not a change of the book: no backup is due for it.
    expect(store!.revision, revision);
    final again = await reopen(ledger);
    expect(again.drafts.of('expense'), contains('1.etr'));
    expect(again.attachmentCommands.receiptFiles, contains('1.etr'));
    again.attachmentCommands.setDraft('expense', null);
    final cleared = await reopen(again);
    expect(cleared.drafts.of('expense'), isNull);
  });
}
