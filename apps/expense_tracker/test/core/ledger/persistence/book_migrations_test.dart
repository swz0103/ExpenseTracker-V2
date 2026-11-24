import 'dart:convert';
import 'dart:io';

import 'package:core/app_core.dart';
import 'package:core/foundation_values.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/ledger/persistence/book_migrations.dart';
import 'package:expense_tracker/src/core/ledger/persistence/record_version.dart';
import 'package:expense_tracker/src/core/ledger/persistence/sql_ledger_data_source.dart';
import 'package:expense_tracker/src/core/ledger/persistence/upgrade_backup.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storage/storage.dart';

/// A book kept by an earlier version is brought up through the steps it
/// lacks, once, in one transaction, after a copy of it is kept. The first
/// steps: a book kept before categories had ids has each category under
/// its name in every record that names one. Opening it must bring every
/// record under the category's id, whole or not at all, and from then on
/// a category renamed must be one row written.
void main() {
  late Directory directory;
  late File file;
  final key = StorageKey.random();
  EncryptedDatabase? store;

  Clock clock() => FixedClock(UtcInstant(DateTime.utc(2026, 10, 4, 4)));

  EncryptedDatabase open() {
    store?.close();
    return store = EncryptedDatabase.open(file, key);
  }

  Future<Ledger> load() => SqlLedgerDataSource(open(), clock: clock()).load();

  /// The records of a book as an earlier version of the app kept them.
  void writeLegacy(EncryptedDatabase s, {bool broken = false}) {
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

  Map<String, Map<String, Object?>> rowsOf(
    EncryptedDatabase s,
    String collection,
  ) => {
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

      expect(ledger.categories.all.map((c) => c.name), [
        '飲食',
        '早餐',
        '交通',
        '薪水',
      ]);
      expect(ledger.categories.all.every((c) => c.id.isNotEmpty), isTrue);
      expect(ledger.category('早餐').parent, '飲食');
      expect(ledger.entries.byId('e1')!.category, '飲食');
      expect(ledger.entries.byId('e2')!.category, '早餐');
      expect(ledger.entries.byId('e3')!.category, '已刪除的分類');
      expect(ledger.entries.byId('e4')!.parts, [('飲食', 100), ('交通', 50)]);
      expect(ledger.budgets.all.map((b) => (b.category, b.limit)).toSet(), {
        ('飲食', 5000),
        ('#家用', 800),
        ('全部支出', 9000),
      });
      expect(ledger.recurring.all.single.category, '交通');
      expect(ledger.trash.all.single.entry.category, '交通');
    },
  );

  test(
    'each record is then kept under the category id, not its name',
    () async {
      writeLegacy(open());
      final ledger = await load();
      final ids = {for (final c in ledger.categories.all) c.name: c.id};
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
    'a record that cannot be read is left as it is, the rest brought up',
    () async {
      writeLegacy(open(), broken: true);
      final ledger = await load();
      // The unreadable entry is set aside, still kept exactly as it was.
      expect(store!.row('entry', 'e5')!.body, '{not json');
      expect(ledger.entries.byId('e5'), isNull);
      expect(ledger.entries.all, hasLength(4));
      expect(ledger.entries.byId('e1')!.category, '飲食');
      expect(
        (jsonDecode(store!.row('entry', 'e1')!.body) as Map)['categoryId'],
        ledger.category('飲食').id,
      );
    },
  );

  test('a step that fails leaves the whole book as it was', () async {
    writeLegacy(open());
    final s = store!;
    final before = [for (final r in s.rows()) (r.shelf, r.id, r.body)];
    void fails(EncryptedDatabase store, RowWriter w) =>
        throw StateError('a later step fails');
    expect(
      () => bringUpBook(s, steps: [...bookSteps, fails]),
      throwsStateError,
    );
    expect([for (final r in s.rows()) (r.shelf, r.id, r.body)], before);
    // Categories are still under their names: nothing was half done.
    expect(rowsOf(s, 'category').keys.toSet(), {'飲食', '早餐', '交通', '薪水'});
    expect(s.meta(EncryptedDatabase.bookVersionKey), isNull);
  });

  test('a book is brought up once, and a copy is kept first', () async {
    writeLegacy(open());
    var copies = 0;
    var steps = 0;
    Future<Ledger> loadCounting() => SqlLedgerDataSource(
      open(),
      clock: clock(),
      beforeUpgrade: () async {
        // The copy is of the book as it was: no step has run yet.
        expect(store!.meta(EncryptedDatabase.bookVersionKey), isNull);
        expect(rowsOf(store!, 'category').keys, contains('飲食'));
        copies++;
        return const UpgradeBackupKept();
      },
    ).load();
    await loadCounting();
    expect(store!.meta(EncryptedDatabase.bookVersionKey), bookVersion);
    await loadCounting();
    expect(copies, 1);
    // A later step reaches a book already at this version, by itself.
    bringUpBook(store!, steps: [...bookSteps, (s, w) => steps++]);
    bringUpBook(store!, steps: [...bookSteps, (s, w) => steps++]);
    expect(steps, 1);
    expect(store!.meta(EncryptedDatabase.bookVersionKey), bookVersion + 1);
  });

  group('a copy that cannot be kept holds the upgrade back (D19)', () {
    const full = FileSystemException(
      'write failed',
      'backups/before-upgrade.etbk',
      OSError('No space left on device', 28),
    );

    test('the disk is full: nothing is brought up, and it says so', () async {
      final s = open();
      writeLegacy(s);
      final before = [for (final r in s.rows()) (r.shelf, r.id, r.body)];
      var copies = 0;
      final source = SqlLedgerDataSource(
        s,
        clock: clock(),
        beforeUpgrade: () => keepUpgradeBackup(() async {
          copies++;
          throw full;
        }),
      );
      final held = await source.bringUp();
      expect(held?.problem, UpgradeBackupProblem.noSpace);
      expect(held?.error, same(full));
      expect(copies, 1);
      // The book as it was: no step ran.
      expect([for (final r in s.rows()) (r.shelf, r.id, r.body)], before);
      expect(s.meta(EncryptedDatabase.bookVersionKey), isNull);
      // Loading it all the same is refused, never brought up unasked.
      await expectLater(source.load(), throwsA(isA<UpgradeHeld>()));
      expect(copies, 2);
      expect(s.meta(EncryptedDatabase.bookVersionKey), isNull);
    });

    test('another failure is told as such', () async {
      final s = open();
      writeLegacy(s);
      final held = await SqlLedgerDataSource(
        s,
        clock: clock(),
        beforeUpgrade: () => keepUpgradeBackup(
          () async => throw const FileSystemException('denied', 'backups'),
        ),
      ).bringUp();
      expect(held?.problem, UpgradeBackupProblem.other);
      expect(s.meta(EncryptedDatabase.bookVersionKey), isNull);
    });

    test('tried again once there is room: kept, then brought up', () async {
      final s = open();
      writeLegacy(s);
      var room = false;
      final source = SqlLedgerDataSource(
        s,
        clock: clock(),
        beforeUpgrade: () => keepUpgradeBackup(() async {
          if (!room) throw full;
        }),
      );
      expect(await source.bringUp(), isNotNull);
      room = true;
      expect(await source.bringUp(), isNull);
      expect(s.meta(EncryptedDatabase.bookVersionKey), bookVersion);
      final ledger = await source.load();
      expect(ledger.entries.all, hasLength(4));
    });

    test('without the copy, when the person chose it: brought up, no copy '
        'asked for', () async {
      final s = open();
      writeLegacy(s);
      var copies = 0;
      final source = SqlLedgerDataSource(
        s,
        clock: clock(),
        beforeUpgrade: () => keepUpgradeBackup(() async {
          copies++;
          throw full;
        }),
      );
      expect(await source.bringUp(withoutBackup: true), isNull);
      expect(copies, 0);
      expect(s.meta(EncryptedDatabase.bookVersionKey), bookVersion);
      final ledger = await source.load();
      expect(ledger.entries.all, hasLength(4));
      expect(copies, 0);
    });
  });

  test('a record naming a category by name is named by id once it is '
      'brought up (DAT-05)', () async {
    // As 0.22.0 kept it: categories by id, but an entry written before its
    // category was made still names it by name.
    final s = open();
    s.write((w) {
      w.put(
        'account',
        'a1',
        jsonEncode({'id': 'a1', 'name': '現金', 'kind': 'cash', 'opening': 0}),
      );
      w.put(
        'category',
        'c-pet',
        jsonEncode({
          'id': 'c-pet',
          'name': '寵物',
          'icon': 'pet',
          'color': 1,
          '_v': 2,
        }),
      );
      w.put(
        'entry',
        'e1',
        jsonEncode({
          'id': 'e1',
          'date': '2026-10-01',
          'type': 'expense',
          'amount': 5,
          'account': 'a1',
          'category': '寵物',
          '_v': 2,
          '_at': 7,
        }),
      );
    });
    var ledger = await load();
    expect(rowsOf(store!, 'entry')['e1'], {
      'id': 'e1',
      'date': '2026-10-01',
      'type': 'expense',
      'amount': 5,
      'account': 'a1',
      'categoryId': 'c-pet',
      '_v': 2,
      '_at': 7,
    });
    ledger.categoryCommands.updateCategory(
      '寵物',
      ledger.category('寵物').copyWith(name: '毛孩'),
    );
    await ledger.settled;
    ledger = await load();
    expect(ledger.entries.byId('e1')!.category, '毛孩');
  });

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

    ledger.categoryCommands.updateCategory(
      '飲食',
      ledger.category('飲食').copyWith(name: '吃飯'),
    );
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
    expect(ledger.entries.byId('e1')!.category, '吃飯');
    expect(ledger.entries.byId('e4')!.parts.first.$1, '吃飯');
    expect(ledger.category('早餐').parent, '吃飯');
    expect(ledger.budgets.all.map((b) => b.category), contains('吃飯'));
    expect(ledger.entries.byId('e3')!.category, '已刪除的分類');
  });

  test(
    'a category edited with a freshly built copy stays the same one',
    () async {
      writeLegacy(open());
      final ledger = await load();
      final old = ledger.category('交通');

      ledger.categoryCommands.updateCategory(
        '交通',
        Category('通勤', old.icon, old.color), // built afresh: its own new id
      );
      await ledger.settled;

      final renamed = ledger.category('通勤');
      expect(renamed.id, old.id);
      expect(rowsOf(store!, 'category').keys, contains(old.id));
      expect(rowsOf(store!, 'category').length, 4);
      expect(ledger.entries.byId('e4')!.parts.last.$1, '通勤');
    },
  );

  test(
    'merging two categories moves the entries and drops the budget',
    () async {
      writeLegacy(open());
      var ledger = await load();
      final from = ledger.category('早餐').id;
      final into = ledger.category('飲食').id;

      ledger.categoryCommands.mergeCategory('早餐', '飲食');
      await ledger.settled;
      expect(ledger.problem.value, isNull);

      final s = store!;
      expect(rowsOf(s, 'category').keys, isNot(contains(from)));
      expect(rowsOf(s, 'entry')['e2']!['categoryId'], into);

      ledger = await load();
      expect(ledger.entries.byId('e2')!.category, '飲食');
      expect(ledger.categories.all.map((c) => c.name), isNot(contains('早餐')));
    },
  );

  test('a category added after is kept under its own id', () async {
    writeLegacy(open());
    var ledger = await load();
    final pet = Category('寵物', 'pet', 0xFF123456);
    ledger.categoryCommands.addCategory(pet);
    ledger.entryCommands.add(
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
    expect(ledger.entries.byId('e7')!.category, '寵物');
  });

  test('a budget removed is dropped under the id it was kept under', () async {
    writeLegacy(open());
    final ledger = await load();
    final id = ledger.category('飲食').id;
    expect(rowsOf(store!, 'budget').keys, contains(id));

    ledger.budgetCommands.removeBudget('飲食');
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

  test('a refund kept without its purchase\'s split and tags is given '
      'them (D65)', () async {
    // As 0.22.0 kept them: a split purchase 飲食 60 + 交通 40 tagged 旅遊,
    // refunded in two halves the way the composer wrote a refund then
    // (the purchase's category, no split, no tags); and a refund that
    // was given a tag of its own.
    final s = open();
    Map<String, Object?> row(Map<String, Object?> json) => {
      ...json,
      'date': '2026-10-01',
      'account': 'a1',
      '_v': 2,
    };
    s.write((w) {
      w.put(
        'account',
        'a1',
        jsonEncode({'id': 'a1', 'name': '現金', 'kind': 'cash', 'opening': 0}),
      );
      for (final (id, name) in [('c-food', '飲食'), ('c-car', '交通')]) {
        w.put(
          'category',
          id,
          jsonEncode({'id': id, 'name': name, 'icon': 'food', 'color': 1}),
        );
      }
      w.put(
        'entry',
        'p',
        jsonEncode(
          row({
            'id': 'p',
            'type': 'expense',
            'amount': 100,
            'categoryId': 'c-food',
            'tags': ['旅遊'],
            'parts': [
              {'categoryId': 'c-food', 'amount': 60},
              {'categoryId': 'c-car', 'amount': 40},
            ],
          }),
        ),
      );
      for (final (id, tags) in [
        ('r1', null),
        ('r2', ['自己的']),
      ]) {
        w.put(
          'entry',
          id,
          jsonEncode(
            row({
              'id': id,
              'type': 'income',
              'amount': 50,
              'categoryId': 'c-food',
              'refundOf': 'p',
              'tags': ?tags,
            }),
          ),
        );
      }
    });
    final ledger = await load();
    // Each half gives back 30 of 飲食 and 20 of 交通.
    expect(rowsOf(store!, 'entry')['r1'], {
      'id': 'r1',
      'type': 'income',
      'amount': 50,
      'categoryId': 'c-food',
      'refundOf': 'p',
      'date': '2026-10-01',
      'account': 'a1',
      '_v': 2,
      'parts': [
        {'categoryId': 'c-food', 'amount': 30},
        {'categoryId': 'c-car', 'amount': 20},
      ],
      'tags': ['旅遊'],
    });
    expect(ledger.entries.byId('r2')!.parts, [('飲食', 30), ('交通', 20)]);
    expect(ledger.entries.byId('r2')!.tags, ['自己的']);
    final october = ledger.reportService.spendingBetween(
      DateTime.utc(2026, 10, 1),
      DateTime.utc(2026, 10, 31),
    );
    expect(october, {'飲食': 0, '交通': 0});
    expect(store!.meta(EncryptedDatabase.bookVersionKey), bookVersion);
  });
}
