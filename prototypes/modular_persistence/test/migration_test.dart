import 'dart:io';

import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:modular_persistence_probe/database.dart';
import 'package:modular_persistence_probe/workflows.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  final root = Directory('.dart_tool/migration-tests')
    ..createSync(recursive: true);
  final workspace = WorkspaceId.parse('019f0000-0000-7000-8000-000000000000');
  final account = PostingAccount(
    id: PublicId.parse('019f0000-0000-7000-8000-000000000001'),
    workspace: workspace,
    currency: Currency('USD', 2),
    expectedVersion: 1,
  );
  late Directory fixture;
  late File file;
  ProbeDatabase? db;
  setUp(() {
    fixture = root.createTempSync('upgrade-');
    file = File('${fixture.path}/finance.db');
    final legacy = sqlite3.open(file.path);
    try {
      legacy.execute(File('test/fixtures/v1.sql').readAsStringSync());
      expect(legacy.select('PRAGMA user_version').single.values.single, 1);
      expect(legacy.select('PRAGMA foreign_key_check'), isEmpty);
    } finally {
      legacy.close();
    }
  });
  tearDown(() async {
    await db?.close();
    db = null;
    if (!fixture.resolveSymbolicLinksSync().startsWith(
      '${root.resolveSymbolicLinksSync()}${Platform.pathSeparator}',
    ))
      throw StateError('Unsafe cleanup.');
    fixture.deleteSync(recursive: true);
  });
  Map<String, List<Map<String, Object?>>> snapshot() {
    final legacy = sqlite3.open(file.path);
    try {
      return {
        for (final table in [
          'accounts',
          'legs',
          'openings',
          'allocations',
          'receipts',
          'audit',
        ])
          table: legacy
              .select('SELECT * FROM $table ORDER BY rowid')
              .map((row) => Map<String, Object?>.from(row))
              .toList(),
        'events': legacy
            .select(
              'SELECT workspace,id,kind,business_date,income,expense,currency,scale FROM events ORDER BY rowid',
            )
            .map((row) => Map<String, Object?>.from(row))
            .toList(),
      };
    } finally {
      legacy.close();
    }
  }

  test(
    'DATA-01 frozen v1 upgrades without changing financial history or receipts',
    () async {
      final before = snapshot();
      db = ProbeDatabase(file);
      final flows = FinancialWorkflows(db!);
      expect(
        await flows.ledger.balance(account),
        Money.parse(account.currency, '115'),
      );
      expect(snapshot(), before);
      expect(
        (await db!.customSelect('PRAGMA user_version').getSingle())
            .data
            .values
            .single,
        2,
      );
      final sources = await db!
          .customSelect('SELECT source_context FROM events')
          .get();
      expect(
        sources.map((row) => row.read<String>('source_context')),
        everyElement('legacy-unspecified'),
      );
      final indexes = await db!
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='index' "
            "AND name IN ('legs_by_account','events_by_date') ORDER BY name",
          )
          .get();
      expect(indexes.map((row) => row.read<String>('name')), [
        'events_by_date',
        'legs_by_account',
      ]);
      final retry = Posting.income(
        id: PublicId.generate(),
        operation: OperationKey(
          workspace,
          OperationId.parse('019f0000-0000-7000-8000-000000000011'),
        ),
        date: BusinessDate(2026, 9, 26),
        account: account,
        amount: Money.parse(account.currency, '20'),
      );
      expect((await flows.post(retry)).replayed, isTrue);
      expect(snapshot(), before);
    },
  );
  test('same-schema open rebuilds only the derived timeline index', () async {
    db = ProbeDatabase(file);
    await db!.customSelect('SELECT * FROM events').get();
    await db!.close();
    db = null;
    final legacy = sqlite3.open(file.path);
    late Map<String, List<Map<String, Object?>>> before;
    try {
      legacy.execute('DROP INDEX events_by_date');
      before = snapshot();
      expect(
        legacy.select(
          "SELECT name FROM sqlite_master WHERE type='index' "
          "AND name='events_by_date'",
        ),
        isEmpty,
      );
    } finally {
      legacy.close();
    }

    db = ProbeDatabase(file);
    await db!.customSelect('SELECT * FROM events').get();
    expect(snapshot(), before);
    final rebuilt = await db!
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type='index' "
          "AND name='events_by_date'",
        )
        .get();
    expect(rebuilt, hasLength(1));
  });
  for (final point in ['column', 'index']) {
    test(
      'DATA-01 failure after $point rolls schema and data back to v1',
      () async {
        final before = snapshot();
        db = ProbeDatabase(
          file,
          migrationCheckpoint: (checkpoint) {
            if (checkpoint == point) throw StateError('injected');
          },
        );
        await expectLater(
          db!.customSelect('SELECT * FROM events').get(),
          throwsStateError,
        );
        await db!.close();
        db = null;
        final legacy = sqlite3.open(file.path);
        try {
          expect(legacy.select('PRAGMA user_version').single.values.single, 1);
          expect(
            legacy
                .select('PRAGMA table_info(events)')
                .map((row) => row['name']),
            isNot(contains('source_context')),
          );
          expect(
            legacy.select(
              "SELECT name FROM sqlite_master WHERE type='index' "
              "AND name IN ('legs_by_account','events_by_date')",
            ),
            isEmpty,
          );
        } finally {
          legacy.close();
        }
        expect(snapshot(), before);
        db = ProbeDatabase(file);
        expect(
          await FinancialWorkflows(db!).ledger.balance(account),
          Money.parse(account.currency, '115'),
        );
      },
    );
  }
  test(
    'unknown future schema is rejected without destructive downgrade',
    () async {
      final future = sqlite3.open(file.path);
      future.execute('PRAGMA user_version = 99');
      future.close();
      final before = snapshot();
      db = ProbeDatabase(file);
      await expectLater(
        db!.customSelect('SELECT * FROM accounts').get(),
        throwsStateError,
      );
      await db!.close();
      db = null;
      expect(snapshot(), before);
      final check = sqlite3.open(file.path);
      try {
        expect(check.select('PRAGMA user_version').single.values.single, 99);
      } finally {
        check.close();
      }
    },
  );
}
