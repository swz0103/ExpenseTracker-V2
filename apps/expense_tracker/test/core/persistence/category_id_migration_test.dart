import 'dart:convert';
import 'dart:io';

import 'package:core/app_core.dart';
import 'package:core/foundation_values.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/ledger/persistence/record_version.dart';
import 'package:expense_tracker/src/core/ledger/persistence/sql_ledger_data_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storage/storage.dart';

/// A book kept before categories had ids has each category under its name
/// in every record that names one. Opening it must bring every record
/// under the category's id, whole or not at all, and from then on a
/// category renamed must be one row written.
void main() {
  late Directory directory;
  late File file;
  final key = StorageKey.random();
  RowStore? store;

  Clock clock() => FixedClock(UtcInstant(DateTime.utc(2026, 10, 4, 4)));

  RowStore open() {
    store?.close();
    return store = RowStore.open(file, key);
  }

  Future<Ledger> load() => SqlLedgerDataSource(open(), clock: clock()).load();

  /// The records of a book as an earlier version of the app kept them.
  void writeLegacy(RowStore s, {bool broken = false}) {
    String row(Map<String, Object?> json) =>
        jsonEncode({...json, '_v': 1, '_at': 1000});
    s.write((w) {
      w.put(
        'account',
        'a1',
        row({'id': 'a1', 'name': '現金', 'kind': 'cash', 'opening': 0}),
      );
      for (final c in [
        {'name': '飲食', 'icon': 'food', 'color': 0xFFD08B5B},
        {'name': '早餐', 'icon': 'food', 'color': 0xFFD08B5B, 'parent': '飲食'},
        {'name': '交通', 'icon': 'travel', 'color': 0xFF5B8DB0},
        {'name': '薪水', 'icon': 'salary', 'color': 0xFF2F7A65, 'income': true},
      ]) {
        w.put('category', c['name']! as String, row(c));
      }
      Map<String, Object?> entry(
        String id,
        String day,
        String category, {
        int amount = 100,
        List<Map<String, Object?>>? parts,
      }) => {
        'id': id,
        'date': day,
        'type': 'expense',
        'amount': amount,
        'account': 'a1',
        'category': category,
        'parts': ?parts,
      };
      w.put('entry', 'e1', row(entry('e1', '2026-10-01', '飲食')));
      w.put('entry', 'e2', row(entry('e2', '2026-10-02', '早餐')));
      w.put('entry', 'e3', row(entry('e3', '2026-10-02', '已刪除的分類')));
      w.put(
        'entry',
        'e4',
        row(
          entry(
            'e4',
            '2026-10-03',
            '飲食',
            amount: 150,
            parts: [
              {'name': '飲食', 'amount': 100},
              {'name': '交通', 'amount': 50},
            ],
          ),
        ),
      );
      w.put('budget', '飲食', row({'category': '飲食', 'limit': 5000}));
      w.put('budget', '#家用', row({'category': '#家用', 'limit': 800}));
      w.put('budget', '全部支出', row({'category': '全部支出', 'limit': 9000}));
      w.put(
        'recurring',
        'r1',
        row({
          'id': 'r1',
          'name': '月票',
          'amount': 1280,
          'day': 5,
          'account': 'a1',
          'category': '交通',
        }),
      );
      w.put(
        'trash',
        'e9',
        row({'on': '2026-10-03', 'entry': entry('e9', '2026-09-30', '交通')}),
      );
      if (broken) w.put('entry', 'e5', '{not json');
    });
  }

  Map<String, Map<String, Object?>> rowsOf(RowStore s, String collection) => {
    for (final r in s.rows(shelf: collection))
      r.id: jsonDecode(r.body) as Map<String, Object?>,
  };

  setUp(() {
    directory = Directory.systemTemp.createTempSync('migration-');
    file = File('${directory.path}/ledger.db');
  });

  tearDown(() {
    store?.close();
    store = null;
    directory.deleteSync(recursive: true);
  });

  test(
    'every record comes back the same, by name, once the book is opened',
    () async {
      writeLegacy(open());
      final ledger = await load();

      expect(ledger.categories.map((c) => c.name), ['飲食', '早餐', '交通', '薪水']);
      expect(ledger.categories.every((c) => c.id.isNotEmpty), isTrue);
      expect(ledger.category('早餐').parent, '飲食');
      expect(ledger.byId('e1')!.category, '飲食');
      expect(ledger.byId('e2')!.category, '早餐');
      expect(ledger.byId('e3')!.category, '已刪除的分類');
      expect(ledger.byId('e4')!.parts, [('飲食', 100), ('交通', 50)]);
      expect(ledger.budgets.map((b) => (b.category, b.limit)).toSet(), {
        ('飲食', 5000),
        ('#家用', 800),
        ('全部支出', 9000),
      });
      expect(ledger.recurring.single.category, '交通');
      expect(ledger.trash.single.entry.category, '交通');
    },
  );

  test(
    'each record is then kept under the category id, not its name',
    () async {
      writeLegacy(open());
      final ledger = await load();
      final ids = {for (final c in ledger.categories) c.name: c.id};
      final s = store!;

      expect(rowsOf(s, 'category').keys.toSet(), ids.values.toSet());
      expect(rowsOf(s, 'category')[ids['飲食']]!['name'], '飲食');
      expect(rowsOf(s, 'category')[ids['早餐']]!['parentId'], ids['飲食']);
      expect(rowsOf(s, 'category')[ids['早餐']]!.containsKey('parent'), isFalse);

      final entries = rowsOf(s, 'entry');
      expect(entries['e1']!['categoryId'], ids['飲食']);
      expect(entries['e1']!.containsKey('category'), isFalse);
      expect(entries['e2']!['categoryId'], ids['早餐']);
      // A name no category has is kept as the name it is.
      expect(entries['e3']!['category'], '已刪除的分類');
      expect(entries['e3']!.containsKey('categoryId'), isFalse);
      expect(entries['e4']!['parts'], [
        {'categoryId': ids['飲食'], 'amount': 100},
        {'categoryId': ids['交通'], 'amount': 50},
      ]);

      // A budget is kept under what it covers: an id, or a tag, or the total.
      expect(rowsOf(s, 'budget').keys.toSet(), {ids['飲食'], '#家用', '全部支出'});
      expect(rowsOf(s, 'recurring')['r1']!['categoryId'], ids['交通']);
      expect(
        (rowsOf(s, 'trash')['e9']!['entry'] as Map)['categoryId'],
        ids['交通'],
      );
      for (final collection in ['category', 'entry', 'budget', 'recurring']) {
        for (final json in rowsOf(s, collection).values) {
          expect(json['_v'], recordVersion, reason: collection);
        }
      }
    },
  );

  test('the order the entries were written in is kept', () async {
    writeLegacy(open());
    await load();
    expect(store!.rows(shelf: 'entry').map((r) => r.id), [
      'e1',
      'e2',
      'e3',
      'e4',
    ]);
    expect(
      store!
          .rows(shelf: 'category')
          .map((r) => (jsonDecode(r.body) as Map)['name']),
      ['飲食', '早餐', '交通', '薪水'],
    );
  });

  test('a book already kept by id is left exactly as it is', () async {
    writeLegacy(open());
    await load();
    final before = [for (final r in store!.rows()) (r.shelf, r.id, r.body)];
    final revision = store!.revision;
    await load();
    expect([for (final r in store!.rows()) (r.shelf, r.id, r.body)], before);
    expect(store!.revision, revision);
  });

  test('the upgrade is not a change a backup is taken for', () async {
    writeLegacy(open());
    final revision = store!.revision;
    await load();
    expect(store!.revision, revision);
  });

  test(
    'a record that cannot be read leaves the whole book as it was',
    () async {
      writeLegacy(open(), broken: true);
      final before = [for (final r in store!.rows()) (r.shelf, r.id, r.body)];
      await expectLater(load(), throwsA(anything));
      expect([for (final r in open().rows()) (r.shelf, r.id, r.body)], before);
      // Categories are still under their names: nothing was half done.
      expect(rowsOf(store!, 'category').keys.toSet(), {'飲食', '早餐', '交通', '薪水'});
    },
  );

  test('renaming a category writes its row and no entry', () async {
    writeLegacy(open());
    var ledger = await load();
    final entriesBefore = {
      for (final r in store!.rows(shelf: 'entry')) r.id: r.body,
    };
    final recurringBefore = store!.rows(shelf: 'recurring').single.body;
    final budgetsBefore = {
      for (final r in store!.rows(shelf: 'budget')) r.id: r.body,
    };
    final id = ledger.category('飲食').id;

    ledger.updateCategory('飲食', ledger.category('飲食').copyWith(name: '吃飯'));
    await ledger.settled;
    expect(ledger.problem.value, isNull);

    final s = store!;
    expect({
      for (final r in s.rows(shelf: 'entry')) r.id: r.body,
    }, entriesBefore);
    expect(s.rows(shelf: 'recurring').single.body, recurringBefore);
    expect({
      for (final r in s.rows(shelf: 'budget')) r.id: r.body,
    }, budgetsBefore);
    expect(rowsOf(s, 'category')[id]!['name'], '吃飯');

    // And after closing and opening, it is the new name everywhere.
    ledger = await load();
    expect(ledger.category('吃飯').id, id);
    expect(ledger.byId('e1')!.category, '吃飯');
    expect(ledger.byId('e4')!.parts.first.$1, '吃飯');
    expect(ledger.category('早餐').parent, '吃飯');
    expect(ledger.budgets.map((b) => b.category), contains('吃飯'));
    expect(ledger.byId('e3')!.category, '已刪除的分類');
  });

  test(
    'a category edited with a freshly built copy stays the same one',
    () async {
      writeLegacy(open());
      final ledger = await load();
      final old = ledger.category('交通');

      ledger.updateCategory(
        '交通',
        Category('通勤', old.icon, old.color), // built afresh: its own new id
      );
      await ledger.settled;

      final renamed = ledger.category('通勤');
      expect(renamed.id, old.id);
      expect(rowsOf(store!, 'category').keys, contains(old.id));
      expect(rowsOf(store!, 'category').length, 4);
      expect(ledger.byId('e4')!.parts.last.$1, '通勤');
    },
  );

  test(
    'merging two categories moves the entries and drops the budget',
    () async {
      writeLegacy(open());
      var ledger = await load();
      final from = ledger.category('早餐').id;
      final into = ledger.category('飲食').id;

      ledger.mergeCategory('早餐', '飲食');
      await ledger.settled;
      expect(ledger.problem.value, isNull);

      final s = store!;
      expect(rowsOf(s, 'category').keys, isNot(contains(from)));
      expect(rowsOf(s, 'entry')['e2']!['categoryId'], into);

      ledger = await load();
      expect(ledger.byId('e2')!.category, '飲食');
      expect(ledger.categories.map((c) => c.name), isNot(contains('早餐')));
    },
  );

  test('a category added after is kept under its own id', () async {
    writeLegacy(open());
    var ledger = await load();
    final pet = Category('寵物', 'pet', 0xFF123456);
    ledger.addCategory(pet);
    ledger.add(
      Entry(
        id: 'e7',
        date: DateTime.utc(2026, 10, 4),
        type: EntryType.expense,
        amount: 300,
        account: 'a1',
        category: '寵物',
      ),
    );
    await ledger.settled;
    expect(rowsOf(store!, 'category').keys, contains(pet.id));
    expect(rowsOf(store!, 'entry')['e7']!['categoryId'], pet.id);

    ledger = await load();
    expect(ledger.category('寵物').id, pet.id);
    expect(ledger.byId('e7')!.category, '寵物');
  });

  test('a budget removed is dropped under the id it was kept under', () async {
    writeLegacy(open());
    final ledger = await load();
    final id = ledger.category('飲食').id;
    expect(rowsOf(store!, 'budget').keys, contains(id));

    ledger.removeBudget('飲食');
    await ledger.settled;
    expect(rowsOf(store!, 'budget').keys, isNot(contains(id)));
    expect(rowsOf(store!, 'budget').keys, contains('#家用'));
  });

  test('a backup written before ids is still accepted', () {
    // What the restore checks of each record of an earlier backup.
    final legacy = {
      'category': jsonEncode({'name': '飲食', 'icon': 'food', 'color': 1}),
      'entry': jsonEncode({
        'id': 'e',
        'date': '2026-10-01',
        'type': 'expense',
        'amount': 1,
        'account': 'a',
        'category': '飲食',
      }),
      'budget': jsonEncode({'category': '飲食', 'limit': 1}),
    };
    for (final MapEntry(key: collection, value: body) in legacy.entries) {
      expect(
        () => SqlLedgerDataSource.check(collection, 'x', body),
        returnsNormally,
        reason: collection,
      );
    }
    // And one by id, whose category is not among the rows checked with it.
    expect(
      () => SqlLedgerDataSource.check(
        'entry',
        'e',
        jsonEncode({
          'id': 'e',
          'date': '2026-10-01',
          'type': 'expense',
          'amount': 1,
          'account': 'a',
          'categoryId': 'someone',
        }),
      ),
      returnsNormally,
    );
  });
}
