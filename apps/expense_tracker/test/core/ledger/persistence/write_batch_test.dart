import 'dart:io';

import 'package:core/app_core.dart';
import 'package:core/foundation_values.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/ledger/persistence/sql_ledger_data_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storage/storage.dart';

/// D119 (`WriteBatch.putBack`): what an undo puts back (a budget, a recurring item, an account,
/// a category) is back in its own place in the order kept, so it stands
/// there still once the app is opened again, not last.
void main() {
  late Directory directory;
  late File file;
  final key = StorageKey.random();
  final clock = FixedClock(UtcInstant(DateTime.utc(2026, 10, 4, 4)));
  EncryptedDatabase? store;

  Ledger? live;

  /// From how many records a change is written on a worker.
  var apartFrom = writeApartFrom;

  /// The book read again from the store, once what it was writing is
  /// kept, as when the app is opened again.
  Future<Ledger> open() async {
    await live?.settled;
    store?.close();
    final opened = store = EncryptedDatabase.open(file, key);
    return live = await SqlLedgerDataSource(
      opened,
      clock: clock,
      writeApartFrom: apartFrom,
    ).load();
  }

  setUp(() {
    directory = Directory.systemTemp.createTempSync('undo-place-');
    file = File('${directory.path}/ledger.db');
  });

  tearDown(() async {
    apartFrom = writeApartFrom;
    await live?.settled;
    live = null;
    store?.close();
    store = null;
    directory.deleteSync(recursive: true);
  });

  Recurring item(String id) => Recurring(
    id: id,
    name: id,
    amount: 100,
    day: 5,
    account: 'bank',
    category: '飲食',
  );

  /// A book with three of each, the middle one to be taken away.
  Future<Ledger> book() async {
    final ledger = await open();
    ledger.entryCommands.addAll(
      const [],
      accounts: const [
        Account('bank', '銀行', AccountKind.bank, 0),
        Account('a1', '甲', AccountKind.cash, 0),
        Account('a2', '乙', AccountKind.cash, 0),
        Account('a3', '丙', AccountKind.cash, 0),
      ],
      categories: [
        Category('飲食', 'food', 0xFF000000),
        Category('交通', 'bus', 0xFF000000),
        Category('居家', 'home', 0xFF000000),
        Category('娛樂', 'fun', 0xFF000000),
      ],
    );
    for (final c in ['飲食', '交通', '居家']) {
      ledger.budgetCommands.setBudget(c, 1000);
    }
    for (final id in ['r1', 'r2', 'r3']) {
      ledger.recurringCommands.saveRecurring(item(id));
    }
    return ledger;
  }

  List<String> accounts(Ledger l) => [for (final a in l.accounts.all) a.id];
  List<String> categories(Ledger l) => [
    for (final c in l.categories.all) c.name,
  ];
  List<String> budgets(Ledger l) => [for (final b in l.budgets.all) b.category];
  List<String> items(Ledger l) => [for (final r in l.recurring.all) r.id];

  test('a budget taken away and put back', () async {
    final ledger = await book();
    final before = budgets(ledger);
    expect(before, ['飲食', '交通', '居家']);
    ledger.budgetCommands.removeBudget('交通')!();
    expect(budgets(ledger), before);
    expect(budgets(await open()), before);
  });

  test('a budget put back by a change written on a worker', () async {
    apartFrom = 1;
    final ledger = await book();
    ledger.budgetCommands.removeBudget('交通')!();
    expect(budgets(await open()), ['飲食', '交通', '居家']);
  });

  test('a recurring item taken away and put back', () async {
    final ledger = await book();
    final before = items(ledger);
    expect(before, ['r1', 'r2', 'r3']);
    ledger.recurringCommands.removeRecurring('r2')!();
    expect(items(ledger), before);
    expect(items(await open()), before);
  });

  test('an account taken away and put back', () async {
    final ledger = await book();
    final before = accounts(ledger);
    expect(before, containsAllInOrder(['bank', 'a1', 'a2', 'a3']));
    ledger.accountCommands.removeAccount('a2')!();
    expect(accounts(ledger), before);
    expect(accounts(await open()), before);
  });

  test('a category merged into another and the merge undone, with its '
      'budget', () async {
    final ledger = await book();
    final before = categories(ledger);
    final budgetsBefore = budgets(ledger);
    expect(before, containsAllInOrder(['飲食', '交通', '居家', '娛樂']));
    final merged = ledger.categoryCommands.mergeCategory('交通', '娛樂');
    (merged as Merged).undo();
    expect(categories(ledger), before);
    expect(budgets(ledger), budgetsBefore);
    final reopened = await open();
    expect(categories(reopened), before);
    expect(budgets(reopened), budgetsBefore);
  });

  test('a tag removed with its budget, and put back', () async {
    final ledger = await book();
    ledger.budgetCommands.setBudget('#旅行', 500);
    ledger.budgetCommands.setBudget('#家用', 500);
    final before = budgets(ledger);
    expect(before, ['飲食', '交通', '居家', '#旅行', '#家用']);
    ledger.entryCommands.renameTag('旅行', '')();
    expect(budgets(ledger), before);
    expect(budgets(await open()), before);
  });

  test('taken away and added anew, not undone, it comes last', () async {
    final ledger = await book();
    ledger.budgetCommands.removeBudget('交通');
    ledger.budgetCommands.setBudget('交通', 1000);
    expect(budgets(await open()), ['飲食', '居家', '交通']);
  });
}
