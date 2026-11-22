import 'dart:convert';
import 'dart:io';

import 'package:core/app_core.dart';
import 'package:core/foundation_values.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/ledger/persistence/book_migrations.dart';
import 'package:expense_tracker/src/core/ledger/persistence/ledger_data_source.dart';
import 'package:expense_tracker/src/core/messages/problem_messages.dart';
import 'package:expense_tracker/src/core/ledger/persistence/quarantine.dart';
import 'package:expense_tracker/src/core/ledger/persistence/sql_ledger_data_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storage/storage.dart';

/// Opening a book: a row that cannot be read is set aside and never
/// written over (DAT-01); a field a later version added is kept when the
/// record is written again (DAT-09); opening writes no starting records
/// into a book opened before (DAT-12); notes of old deletions are let go
/// (DAT-08).
void main() {
  late Directory directory;
  late File file;
  final key = StorageKey.random();
  var now = DateTime.utc(2026, 10, 4, 4);
  EncryptedDatabase? store;
  late SqlLedgerDataSource source;

  EncryptedDatabase open() {
    store?.close();
    return store = EncryptedDatabase.open(file, key);
  }

  Future<Ledger> load() {
    source = SqlLedgerDataSource(open(), clock: FixedClock(UtcInstant(now)));
    return source.load();
  }

  Map<String, Object?> row(String shelf, String id) =>
      jsonDecode(store!.row(shelf, id)!.body) as Map<String, Object?>;

  Map<String, Object?> entry(String id, {int amount = 100}) => {
    'id': id,
    'date': '2026-10-01',
    'type': 'expense',
    'amount': amount,
    'account': 'a1',
  };

  setUp(() {
    directory = Directory.systemTemp.createTempSync('opening-');
    file = File('${directory.path}/ledger.db');
    now = DateTime.utc(2026, 10, 4, 4);
  });

  tearDown(() {
    store?.close();
    store = null;
    directory.deleteSync(recursive: true);
  });

  group('a row that cannot be read', () {
    test('is set aside with why, and the rest of each kind opens', () async {
      await load();
      store!.write((w) {
        w.put(
          'account',
          'a1',
          jsonEncode({'id': 'a1', 'name': '現金', 'kind': 'cash', 'opening': 0}),
        );
        w.put('account', 'a2', jsonEncode({'id': 'a2', 'kind': 'cash'}));
        w.put('category', 'c9', '{"id":"c9","name":');
        w.put('entry', 'e1', jsonEncode(entry('e1')));
        w.put('entry', 'e2', jsonEncode({...entry('e2'), '_v': 7}));
        w.put('entry', 'e3', '[1,2]');
        w.put('trash', 'e4', jsonEncode({'on': '2026-10-03'}));
      });
      final ledger = await load();

      expect(ledger.entries.all.map((e) => e.id), ['e1']);
      expect(ledger.accounts.all.map((a) => a.id), contains('a1'));
      expect(ledger.accounts.all.map((a) => a.id), isNot(contains('a2')));
      expect(ledger.categories.all, hasLength(9));
      expect(ledger.trash.all, isEmpty);
      final aside = {for (final q in source.quarantined) q.key: q};
      expect(aside.keys.toSet(), {
        'account/a2',
        'category/c9',
        'entry/e2',
        'entry/e3',
        'trash/e4',
      });
      expect(aside['category/c9']!.reason, QuarantineReason.unreadable);
      expect(aside['entry/e3']!.reason, QuarantineReason.unreadable);
      expect(aside['entry/e2']!.reason, QuarantineReason.newer);
      expect(aside['entry/e2']!.version, 7);
      expect(aside['account/a2']!.reason, QuarantineReason.invalid);
      expect(aside['trash/e4']!.reason, QuarantineReason.invalid);
      // Every row is still kept exactly as it was.
      expect(store!.row('entry', 'e3')!.body, '[1,2]');
      expect(store!.row('category', 'c9')!.body, '{"id":"c9","name":');
    });

    test('is told without anything the person wrote in it', () async {
      await load();
      store!.write((w) {
        w.put(
          'entry',
          'e1',
          jsonEncode({...entry('e1'), 'amount': '4321', 'note': '祕密的午餐'}),
        );
      });
      await load();
      final detail = source.quarantined.single.detail;
      expect(detail, 'FormatException: Expected a whole number');
      expect(detail, isNot(contains('4321')));
      expect(detail, isNot(contains('祕密')));
    });

    test('is never written over, nor dropped as old trash', () async {
      var ledger = await load();
      final food = ledger.category('飲食日常').id;
      const newer = '{"categoryId":"%s","limit":1,"_v":99}';
      final budget = newer.replaceFirst('%s', food);
      store!.write((w) {
        w.put('budget', food, budget);
        // Put in the trash 40 days ago, by a later version.
        w.put(
          'trash',
          'old',
          jsonEncode({'on': '2026-08-25', 'entry': entry('old'), '_v': 99}),
        );
      });
      ledger = await load();
      expect(ledger.budgets.all, isEmpty);

      // The screens know no budget there: setting one would write over
      // the row set aside, so the change is refused and read back.
      ledger.budgetCommands.setBudget('飲食日常', 500);
      await ledger.settled;
      expect(
        ledger.problem.value,
        isA<KeepFailed>().having(
          (p) => (p.cause as DataSourceException).cause,
          'cause',
          isA<RowSetAside>(),
        ),
      );
      expect(
        describeProblem(ledger.problem.value!),
        '這筆變更會覆蓋一筆讀不出來、已隔離的資料，為了保護它沒有存下。',
      );
      expect(store!.row('budget', food)!.body, budget);
      expect(store!.row('trash', 'old'), isNotNull);
    });

    test(
      'of a later version leaves the rest of the book open as usual',
      () async {
        await load();
        store!.write((w) => w.setMeta(bookVersionKey, bookVersion + 5));
        final ledger = await load();
        expect(ledger.accounts.all, hasLength(2));
        // Not taken back to this version's number.
        expect(store!.meta(bookVersionKey), bookVersion + 5);
      },
    );
  });

  group('a field this version does not know', () {
    test('is kept when its record is changed here', () async {
      var ledger = await load();
      final cash = ledger.accounts.all.first;
      store!.write((w) {
        w.put(
          'entry',
          'e1',
          jsonEncode({
            ...entry('e1'),
            'account': cash.id,
            'mood': 'happy',
            '_v': 2,
          }),
        );
        w.put(
          'account',
          cash.id,
          jsonEncode({
            'id': cash.id,
            'name': cash.name,
            'kind': 'cash',
            'opening': 0,
            'bankCode': '700',
          }),
        );
      });
      ledger = await load();
      final e1 = ledger.entries.byId('e1')!;
      ledger.entryCommands.replace(
        Entry(
          id: e1.id,
          date: e1.date,
          type: e1.type,
          amount: 250,
          account: e1.account,
        ),
      );
      ledger.accountCommands.updateAccount(
        ledger.accounts.all.first.copyWith(name: '錢包'),
      );
      await ledger.settled;
      expect(ledger.problem.value, isNull);
      expect(row('entry', 'e1')['amount'], 250);
      expect(row('entry', 'e1')['mood'], 'happy');
      expect(row('account', cash.id)['name'], '錢包');
      expect(row('account', cash.id)['bankCode'], '700');
    });

    test('goes with an entry to the trash and back', () async {
      var ledger = await load();
      final cash = ledger.accounts.all.first;
      store!.write((w) {
        w.put(
          'entry',
          'e1',
          jsonEncode({...entry('e1'), 'account': cash.id, 'mood': 'happy'}),
        );
      });
      ledger = await load();
      ledger.entryCommands.remove('e1');
      await ledger.settled;
      expect((row('trash', 'e1')['entry']! as Map)['mood'], 'happy');

      ledger = await load();
      ledger.entryCommands.restoreTrashed(ledger.trash.all.single);
      await ledger.settled;
      expect(row('entry', 'e1')['mood'], 'happy');
    });

    test(
      'a field it knows, left out as the default, is not brought back',
      () async {
        var ledger = await load();
        final cash = ledger.accounts.all.first;
        ledger.accountCommands.updateAccount(cash.copyWith(archived: true));
        await ledger.settled;
        expect(row('account', cash.id)['archived'], true);
        ledger = await load();
        ledger.accountCommands.updateAccount(
          ledger.accounts.byId(cash.id)!.copyWith(archived: false),
        );
        await ledger.settled;
        expect(row('account', cash.id).containsKey('archived'), isFalse);
      },
    );
  });

  group('the starting records', () {
    test('are given to a new book only, not again once removed', () async {
      final ledger = await load();
      expect(ledger.accounts.all, hasLength(2));
      expect(store!.meta(bookVersionKey), bookVersion);
      store!.write((w) {
        for (final a in ledger.accounts.all) {
          w.drop('account', a.id);
        }
      });
      final again = await load();
      expect(again.accounts.all, isEmpty);
      expect(store!.rows(shelf: 'account'), isEmpty);
    });

    test('are not given to a book an earlier version kept', () async {
      // As 0.22.0 kept a book whose person removed every account: no
      // version noted, categories but no accounts.
      final s = open();
      s.write((w) {
        w.put(
          'category',
          'c1',
          jsonEncode({'id': 'c1', 'name': '飲食', 'icon': 'food', 'color': 1}),
        );
      });
      final revision = s.revision;
      final ledger = await load();
      expect(ledger.accounts.all, isEmpty);
      expect(ledger.categories.all.map((c) => c.name), ['飲食']);
      expect(store!.meta(bookVersionKey), bookVersion);
      // Opening wrote no change of the book.
      expect(store!.revision, revision);
    });
  });

  test('notes of deletions are let go once the trash would be', () async {
    await load();
    // 2026-10-04 less 30 days is 2026-09-04: one note before, one after.
    final before = DateTime.utc(2026, 9, 3).millisecondsSinceEpoch;
    final after = DateTime.utc(2026, 9, 5).millisecondsSinceEpoch;
    store!.write((w) {
      w.put('gone', 'entry/old', jsonEncode({'at': before}));
      w.put('gone', 'entry/new', jsonEncode({'at': after}));
      w.put('gone', 'entry/odd', 'not a note');
    });
    final revision = store!.revision;
    await load();
    expect(store!.rows(shelf: 'gone').map((r) => r.id), [
      'entry/new',
      'entry/odd',
    ]);
    // Letting the notes go is not a change of the book.
    expect(store!.revision, revision);
  });
}
