import 'dart:async';
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
  EncryptedDatabase? store;

  Clock clock() => FixedClock(UtcInstant(now));

  Future<Ledger> reopen([Ledger? ledger]) async {
    if (ledger != null) {
      await ledger.settled;
      expect(ledger.problem.value, isNull);
    }
    store?.close();
    final opened = EncryptedDatabase.open(file, key);
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
    final opened = EncryptedDatabase.open(file, key);
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
      ..entryCommands.replace(
        ledger.entries.byId(lunch.id)!,
        receipt: 'lunch.etr',
      );
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

  test('a change written apart keeps the same rows as one written at once '
      '(DAT-03)', () async {
    // Two books on the same clock: one writes every change apart (from
    // one record), the other every change at once.
    final apart = EncryptedDatabase.open(file, key);
    final other = EncryptedDatabase.open(
      File('${directory.path}/other.db'),
      key,
    );
    addTearDown(apart.close);
    addTearDown(other.close);
    final sources = [
      SqlLedgerDataSource(apart, clock: clock(), writeApartFrom: 1),
      SqlLedgerDataSource(other, clock: clock(), writeApartFrom: 1 << 30),
    ];
    for (final s in sources) {
      await s.load();
    }
    // Ids of their own: the starting accounts and categories of each book
    // are made with new ids, so only these rows are compared.
    const account = Account('wallet', '零錢', AccountKind.cash, 0);
    Entry lunch(int i) => Entry(
      id: 'e$i',
      date: DateTime.utc(2026, 10, 1 + i),
      type: EntryType.expense,
      amount: 100 + i,
      account: account.id,
      category: '午餐',
      merchant: '全聯',
    );
    final batches = [
      WriteBatch(
        accounts: [account],
        entries: [for (var i = 0; i < 3; i++) lunch(i)],
        receipts: {'e0': 'e0.etr'},
        drafts: {'expense': '{"amount":"12"}'},
      ),
      WriteBatch(
        entries: [lunch(1).withLabels(merchant: '全聯福利中心')],
        trash: [Trashed(lunch(2), DateTime.utc(2026, 10, 4))],
        dropped: [(Collection.entry, 'e2')],
        receipts: {'e0': null},
        drafts: {'expense': null},
      ),
    ];
    for (final batch in batches) {
      for (final s in sources) {
        await s.keep(batch);
      }
    }
    List<(String, String, String)> rows(EncryptedDatabase db) => [
      for (final r in db.rows())
        if (r.shelf != 'category' && (r.shelf != 'account' || r.id == 'wallet'))
          (r.shelf, r.id, r.body),
    ];
    expect(rows(apart), rows(other));
    // The wallet, e0 and e1, e2 in the trash and the note of its going;
    // the photo and the form put aside were taken away again.
    expect(
      [for (final (shelf, id, _) in rows(apart)) '$shelf/$id'],
      ['account/wallet', 'entry/e0', 'entry/e1', 'trash/e2', 'gone/entry/e2'],
    );
    // A new book's first write, then the two changes.
    expect((apart.revision, other.revision), (3, 3));
    expect(apart.busyApart, isFalse);
  });

  test('a change kept while a backup reads the book waits for the read, '
      'and is kept after it (D41)', () async {
    final s = EncryptedDatabase.open(file, key);
    store = s;
    final source = SqlLedgerDataSource(s, clock: clock());
    final ledger = await source.load();
    s.write((w) {
      for (var i = 0; i < 20000; i++) {
        w.put('price', 'p$i', '{}');
      }
    }, counts: false);
    final before = s.revision;
    final reading = s.readApart(_rowsRead);
    expect(s.busyApart, isTrue);
    // As the screens keep a change: one record, written at once.
    final keeping = source.keep(
      WriteBatch(accounts: [Account('wallet', '零錢', AccountKind.cash, 0)]),
    );
    final read = await reading;
    await keeping;
    expect(ledger.problem.value, isNull);
    // What the backup read is the book before the change.
    expect(read.revision, before);
    expect(read.ids, isNot(contains('wallet')));
    // The change is kept after it.
    expect(s.revision, before + 1);
    expect(s.row('account', 'wallet'), isNotNull);
  });

  test('a backup starting the moment the last one ends does not come '
      'between the wait and the write (D41)', () async {
    final s = EncryptedDatabase.open(file, key);
    store = s;
    final source = SqlLedgerDataSource(s, clock: clock());
    final ledger = await source.load();
    final before = s.revision;
    final first = s.readApart(_rowsRead);
    // The change waits for the first read to end.
    final keeping = source.keep(
      WriteBatch(accounts: [Account('wallet', '零錢', AccountKind.cash, 0)]),
    );
    // A second backup starts as soon as the first is done, in the turn
    // after the change's own wait saw the store free: where it once
    // found the store taken as it went to write, and the change was lost.
    Future<({int revision, Set<String> ids})>? second;
    unawaited(s.idle.then((_) => second = s.readApart(_rowsRead)));
    await first;
    await keeping;
    expect(ledger.problem.value, isNull);
    // The change was written as the store was seen free, so the second
    // read is one state of the book: the one with the change.
    final read = await second!;
    expect(read.ids, contains('wallet'));
    expect(read.revision, before + 1);
    expect(s.revision, before + 1);
    expect(s.row('account', 'wallet'), isNotNull);
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
    // The store is closed: the change is refused, and so is reading the
    // book back, which is what is told last.
    expect(
      ledger.problem.value,
      isA<ReloadFailed>().having(
        (p) => p.cause,
        'cause',
        isA<DataSourceException>(),
      ),
    );
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
        throwsA(isA<FormatException>()),
        reason: '$collection $body',
      );
    }
  });

  test('a malformed backup row is a FormatException naming it (DAT-13)', () {
    final cases = {
      // A version that is no number, or no finite one.
      'entry': [
        '{"_v":"2","id":"e","date":"2026-10-04","type":"expense","amount":1,"account":"a"}',
        '{"_v":1e400,"id":"e","date":"2026-10-04","type":"expense","amount":1,"account":"a"}',
        '{"id":"e","date":"2026-10-04","type":"expense","amount":-5,"account":"a"}',
        '{"id":"e","date":"2026-10-04","type":"transfer","amount":5,"account":"a"}',
        '{"id":"e","date":"2026-10-04","type":"expense","amount":"5","account":"a"}',
      ],
      'recurring': [
        '{"id":"r","name":"r","amount":1,"day":1,"account":"a","category":"c","every":0}',
        '{"id":"r","name":"r","amount":1,"day":40,"account":"a","category":"c"}',
        '{"id":"r","name":"r","amount":-1,"day":1,"account":"a","category":"c"}',
      ],
      'account': [
        '{"id":"k","name":"k","kind":"card","opening":0,"closingDay":0}',
        '{"id":"k","name":"k","kind":"card","opening":0,"dueDay":32}',
      ],
      'budget': [
        '{"category":"c","limit":-1}',
        '{"category":"c","limit":1,"warning":0}',
      ],
    };
    for (final MapEntry(key: collection, value: bodies) in cases.entries) {
      for (final body in bodies) {
        expect(
          () => SqlLedgerDataSource.check(collection, 'row1', body),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              startsWith('$collection row1: '),
            ),
          ),
          reason: body,
        );
      }
    }
  });

  test('an old row the write rules would refuse still restores', () {
    // An amount of nothing, a foreign spending without its NT$ worth, an
    // end before the start: kept by older versions, read as they are.
    SqlLedgerDataSource.check(
      'entry',
      'e',
      '{"id":"e","date":"2026-10-04","type":"expense","amount":0,"account":"usd"}',
    );
    SqlLedgerDataSource.check(
      'recurring',
      'r',
      '{"id":"r","name":"r","amount":0,"day":5,"account":"a","category":"c",'
          '"start":"2026-05-01","end":"2026-04-01"}',
    );
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
    final opened = EncryptedDatabase.open(file, key);
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

  test(
    'a large book opens a page at a time, the screen drawn between',
    () async {
      final opened = EncryptedDatabase.open(file, key);
      store = opened;
      await SqlLedgerDataSource(opened, clock: clock()).keep(
        WriteBatch(
          entries: [
            for (var i = 0; i < 1500; i++)
              Entry(
                id: 'e$i',
                date: DateTime.utc(2026, 1 + i % 12, 1 + i % 28),
                type: EntryType.expense,
                amount: 100,
                account: 'bank',
                category: '飲食',
              ),
          ],
        ),
      );
      // A frame waiting while the book opens gets its turn before the book
      // is open, as it would not if the whole book were read in one go.
      var drawn = 0;
      var open = false;
      Timer.run(() => drawn += open ? 0 : 1);
      // Fewer rows than are decoded apart, so only the reading lets a
      // frame in.
      final loading = SqlLedgerDataSource(
        opened,
        clock: clock(),
        readPage: 500,
      ).load();
      final ledger = await loading;
      open = true;
      expect(drawn, 1);
      expect(ledger.entries.all, hasLength(1500));
    },
  );
}

/// What a backup's read found: its revision and the ids of the records,
/// on the worker (sent there: no store along).
Future<({int revision, Set<String> ids})> _rowsRead(StoreSnapshot s) async =>
    (revision: s.revision, ids: {for (final r in s.rows) r.id});
