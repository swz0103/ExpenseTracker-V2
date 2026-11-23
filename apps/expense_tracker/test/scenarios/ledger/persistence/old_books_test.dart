import 'dart:convert';
import 'dart:io';

import 'package:core/app_core.dart';
import 'package:core/foundation_values.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/ledger/persistence/record_version.dart';
import 'package:expense_tracker/src/core/ledger/persistence/sql_ledger_data_source.dart';
import 'package:expense_tracker/src/features/entries/model/compose_draft.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storage/storage.dart';
import 'package:vault/backup_security.dart';
import 'package:vault/ledger_backup.dart';
import 'package:vault/ledger_vault.dart';

import '../../../support/book_records.dart';

/// A book and a backup kept by each version of the app, byte for byte as
/// it wrote them, must open in this one and hold the same records
/// (docs/adr/0010-data-that-lasts.md). One kept per minor version is
/// checked on every change; `MAKE_FIXTURES=1` writes the one for this
/// version.
const _books = 'test/fixtures/books';
const _password = 'fixture password';
final _clock = FixedClock(UtcInstant(DateTime.utc(2026, 10, 4, 4)));
final _receipt = utf8.encode('a receipt photo, sealed as the app keeps it');

/// The codec the app opens books with (`bootstrap.dart`).
KeyringCodec _codec() => KeyringCodec(minimumPassword: 6);

/// The record version of the books kept before records.json said it.
const _recordVersionBefore = {'0.17.0': 2, '0.18.0': 2};

String _appVersion() {
  final line = File('pubspec.yaml')
      .readAsLinesSync()
      .firstWhere((l) => l.startsWith('version:'));
  return line.substring('version:'.length).trim().split('+').first;
}

Future<Ledger> _load(EncryptedDatabase store) =>
    SqlLedgerDataSource(store, clock: _clock).load();

void main() {
  late Directory scratch;
  setUp(() => scratch = Directory.systemTemp.createTempSync('old-books-'));
  tearDown(() => scratch.deleteSync(recursive: true));

  test('each minor version keeps a book for later versions to open', () {
    // A release without one could change the format unnoticed. A format
    // change raises the minor version at least (ADR-0011), so one book
    // per minor version is enough; a fix (0.20.1) writes none.
    final current = _appVersion();
    final minor = current.substring(0, current.lastIndexOf('.'));
    expect(
      Directory(_books).listSync().whereType<Directory>().any(
        (d) => d.uri.pathSegments
            .where((s) => s.isNotEmpty)
            .last
            .startsWith('$minor.'),
      ),
      isTrue,
      reason:
          'run MAKE_FIXTURES=1 flutter test '
          'test/scenarios/ledger/persistence/old_books_test.dart',
    );
  }, skip: Platform.environment['MAKE_FIXTURES'] != null);

  for (final dir
      in Directory(_books).existsSync()
          ? (Directory(_books).listSync().whereType<Directory>().toList()
              ..sort((a, b) => a.path.compareTo(b.path)))
          : <Directory>[]) {
    final version = dir.uri.pathSegments.where((s) => s.isNotEmpty).last;
    final written =
        (jsonDecode(
          File('${dir.path}/records.json').readAsStringSync(),
        ) as Map<String, Object?>).map(
          (k, v) => MapEntry(k, [for (final s in v! as List) s as String]),
        );
    // Through this version's own upgrade steps: a record whose shape
    // changed since compares equal, and the kept file is never edited.
    final expected = upgradeRecords(
      written,
      switch (written[recordVersionKey]) {
        [final v] => int.parse(v),
        _ => _recordVersionBefore[version]!,
      },
    );

    test('the book kept by $version opens with its password', () async {
      final copy = Directory('${scratch.path}/vault')..createSync();
      for (final f in Directory('${dir.path}/vault').listSync()) {
        if (f is File) f.copySync('${copy.path}/${f.uri.pathSegments.last}');
      }
      final open = await LedgerVault(
        copy,
        codec: _codec(),
      ).unlockWithPassword(_password);
      addTearDown(open.close);
      expect(canonicalRecords(bookRecords(await _load(open.store))), expected);
    });

    test('the backup kept by $version restores the same book', () async {
      final file = File('${dir.path}/backup.etbk');
      final header = await LedgerBackup.readHeader(file);
      final keys = await _codec().unlockWithPassword(header.keyring, _password);
      final into = EncryptedDatabase.open(
        File('${scratch.path}/restored.db'),
        StorageKey.random(),
      );
      addTearDown(into.close);
      final files = <String, List<int>>{};
      await LedgerBackup.restore(
        file: file,
        keys: keys,
        into: into,
        accept: SqlLedgerDataSource.check,
        onFile: (name, bytes) async => files[name] = bytes,
      );
      expect(canonicalRecords(bookRecords(await _load(into))), expected);
      expect(files, {'r1.etr': _receipt});
    });
  }

  test('a kept record is brought up by the upgrade steps alone', () {
    const kept = {
      recordVersionKey: ['2'],
      'accounts': ['{"opening":50000,"id":"bank"}'],
      'order of accounts': ['bank'],
    };
    // A later version renames a field and adds the step for it.
    Map<String, Object?> rename(String collection, Map<String, Object?> json) =>
        (json['_v']! as int) < 3 && collection == 'account'
        ? ({...json, 'start': json['opening']}..remove('opening'))
        : json;
    expect(upgradeRecords(kept, 2, upgrade: rename), {
      'accounts': ['{"id":"bank","start":50000}'],
      'order of accounts': ['bank'],
    });
    // Without it the record stays as it was written, and so differs from
    // what the later version writes.
    expect(upgradeRecords(kept, 2, upgrade: (_, json) => json)['accounts'], [
      '{"id":"bank","opening":50000}',
    ]);
  });

  test('writes the book and backup this version keeps', () async {
    final out = Directory('$_books/${_appVersion()}');
    if (out.existsSync()) out.deleteSync(recursive: true);
    final vaultDir = Directory('${out.path}/vault')
      ..createSync(recursive: true);
    final (open, _) = await LedgerVault(
      vaultDir,
      codec: _codec(),
    ).create(_password);
    final live = await _load(open.store);
    _fill(live);
    await live.settled;
    expect(live.problem.value, isNull);
    File('${out.path}/records.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        recordVersionKey: ['$recordVersion'],
        ...bookRecords(live),
      }),
    );
    final receipt = File('${scratch.path}/r1.etr')..writeAsBytesSync(_receipt);
    await LedgerBackup.write(
      store: open.store,
      keys: open.keys,
      file: File('${out.path}/backup.etbk'),
      backupId: 'fixture-$version',
      createdAt: DateTime.utc(2026, 10, 4, 4),
      files: {'r1.etr': receipt},
    );
    open.close();
  }, skip: Platform.environment['MAKE_FIXTURES'] == null);
}

/// The version being written, for the backup's id.
final version = _appVersion();

/// Every kind of record the book keeps, each in its less usual forms too.
void _fill(Ledger live) {
  final day = DateTime.utc(2026, 10, 4);
  DateTime ago(int days) => day.subtract(Duration(days: days));
  live.entryCommands.addAll(
    const [],
    accounts: [
      const Account('bank', '銀行', AccountKind.bank, 50000),
      const Account('cash', '現金', AccountKind.cash, 2000, icon: 'wallet'),
      const Account(
        'card',
        '信用卡',
        AccountKind.card,
        0,
        closingDay: 20,
        dueDay: 5,
        limit: 80000,
      ),
      const Account('usd', '美元', AccountKind.bank, 10000, currency: 'USD'),
      const Account('ann', '阿安', AccountKind.receivable, 0),
      const Account('old', '舊帳戶', AccountKind.cash, 0, archived: true),
    ],
    categories: [
      Category('飲食', 'food', 0xFFD08B5B),
      Category('早餐', 'food', 0xFFD08B5B, parent: '飲食'),
      Category('居家', 'home', 0xFF5C9A83),
      Category('舊分類', 'other', 0xFF888888, archived: true),
      Category('薪水', 'salary', 0xFF2F7A65, income: true),
    ],
  );
  final c = live.entryCommands;
  Entry e(
    String id,
    int days,
    EntryType type,
    int amount, {
    String account = 'bank',
    String? to,
    String category = '',
    String note = '',
    String merchant = '',
    List<String> tags = const [],
    int installments = 1,
    String? holding,
    int shares = 0,
    int? received,
  }) => Entry(
    id: id,
    date: ago(days),
    type: type,
    amount: amount,
    account: account,
    to: to,
    category: category,
    note: note,
    merchant: merchant,
    tags: tags,
    installments: installments,
    holding: holding,
    shares: shares,
    received: received,
  );
  c
    ..add(
      e(
        'lunch',
        1,
        EntryType.expense,
        120,
        category: '早餐',
        merchant: '早餐店',
        tags: ['家用'],
        note: '蛋餅',
      ),
      receipt: 'r1.etr',
    )
    ..add(e('pay', 3, EntryType.income, 52000, category: '薪水'))
    ..add(e('move', 2, EntryType.transfer, 1000, to: 'cash'))
    ..add(e('fx', 5, EntryType.transfer, 3210, to: 'usd', received: 10000))
    ..add(
      e(
        'tv',
        20,
        EntryType.expense,
        10001,
        account: 'card',
        category: '居家',
        installments: 3,
      ),
    )
    ..add(e('buy', 30, EntryType.buy, 60000, holding: '2330', shares: 100))
    ..add(e('sell', 10, EntryType.sell, 33000, holding: '2330', shares: 50))
    ..add(e('div', 8, EntryType.dividend, 450, holding: '2330'))
    ..add(e('gone', 4, EntryType.expense, 80, category: '飲食'));
  c.save([
    Entry(
      id: 'meal',
      date: ago(6),
      type: EntryType.expense,
      amount: 600,
      account: 'bank',
      category: '飲食',
      group: 'g1',
    ),
    Entry(
      id: 'meal-ann',
      date: ago(6),
      type: EntryType.transfer,
      amount: 300,
      account: 'bank',
      to: 'ann',
      category: '',
      group: 'g1',
    ),
  ]);
  c.remove('gone');
  live.budgetCommands
    ..setBudget(allSpending, 30000, warning: 90, carry: true)
    ..setBudget('飲食', 6000)
    ..setBudget('#家用', 3000);
  live.recurringCommands
    ..saveRecurring(
      Recurring(
        id: 'rent',
        name: '房租',
        amount: 12500,
        day: 1,
        account: 'bank',
        category: '居家',
        auto: true,
        start: DateTime.utc(2026, 1, 1),
      ),
    )
    ..saveRecurring(
      Recurring(
        id: 'gym',
        name: '健身房',
        amount: 990,
        day: 15,
        account: 'card',
        category: '居家',
        unit: RepeatUnit.week,
        every: 2,
        start: DateTime.utc(2026, 9, 1),
        active: false,
      ),
    );
  // A form put aside as the entry form keeps it, with a share for someone.
  live.attachmentCommands.setDraft(
    'expense',
    ComposeDraft(e('draft', 0, EntryType.expense, 99, category: '飲食'), null, [
      ('ann', 40),
    ]).toJson(),
  );
}
