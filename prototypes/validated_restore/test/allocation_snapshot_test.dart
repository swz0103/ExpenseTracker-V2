import 'dart:convert';
import 'dart:io';

import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:modular_persistence_probe/categories_adapter.dart';
import 'package:modular_persistence_probe/database.dart';
import 'package:modular_persistence_probe/storage_binding.dart';
import 'package:modular_persistence_probe/workflows.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:validated_restore_probe/snapshot.dart';

import 'package:modular_persistence_probe/fixture_allocation.dart';

void main() {
  final root = Directory('.dart_tool/allocation-snapshot-tests')
    ..createSync(recursive: true);
  final codec = SnapshotCodec(categoryReferences: true);
  late Directory work;
  late List<int> bytes;
  late AllocationFixture fixture;
  late Posting expense;
  late StorageBinding sourceBinding;
  setUp(() async {
    work = root.createTempSync('case-');
    sourceBinding = allocationBinding();
    final db = ProbeDatabase(
      File('${work.path}/source'),
      storageBinding: sourceBinding,
      categoryReferences: true,
    );
    fixture = AllocationFixture(db);
    try {
      await fixture.initialize();
      expense = fixture.expense(
        allocations: [
          Allocation(
            fixture.food,
            fixture.money('6'),
            expectedCategoryVersion: 1,
          ),
          Allocation(
            fixture.travel,
            fixture.money('4'),
            expectedCategoryVersion: 1,
          ),
        ],
      );
      await FinancialWorkflows(db).post(expense);
      await FinancialWorkflows(db).post(fixture.income());
      final adapter = CategoriesAdapter(db);
      await adapter.mutate(
        fixture.operation(),
        CategoryMutation.rename(fixture.food, 1, '舊飲食'),
      );
      await adapter.mutate(
        fixture.operation(),
        CategoryMutation.merge(fixture.food, 2, fixture.travel, 1),
      );
      await adapter.mutate(
        fixture.operation(),
        CategoryMutation.archive(fixture.travel, 1, true),
      );
      await adapter.mutate(
        fixture.operation(),
        CategoryMutation.archive(fixture.salary, 1, true),
      );
      bytes = await codec.capture(db);
    } finally {
      await db.close();
    }
  });
  tearDown(() {
    if (!work.absolute.path.startsWith(
      '${root.absolute.path}${Platform.pathSeparator}',
    ))
      throw StateError('Unsafe cleanup');
    work.deleteSync(recursive: true);
  });
  Future<void> stage(
    List<int> input,
    String name, {
    void Function(String)? checkpoint,
  }) => codec.stage(
    input,
    File('${work.path}/$name'),
    checkpoint: checkpoint,
    openDatabase: (f) => ProbeDatabase(
      f,
      storageBinding: allocationBinding(),
      categoryReferences: true,
    ),
  );

  test('snapshot 4 ledger 3 validates historical selections after merge and archive', () async {
    final parsed = jsonDecode(utf8.decode(bytes)) as Map;
    expect(parsed['version'], 4);
    expect(parsed['schema'], 5);
    expect(parsed['modules']['ledger'], 3);
    final binding = allocationBinding(), file = File('${work.path}/restored');
    await codec.stage(
      bytes,
      file,
      openDatabase: (f) =>
          ProbeDatabase(f, storageBinding: binding, categoryReferences: true),
    );
    final restored = ProbeDatabase(
      file,
      storageBinding: binding,
      categoryReferences: true,
    );
    try {
      expect(await codec.capture(restored), bytes);
      expect(
        await FinancialWorkflows(restored).ledger.balance(fixture.reference),
        fixture.money('110'),
      );
      expect(
        (await FinancialWorkflows(restored).post(expense)).replayed,
        isTrue,
      );
      expect(await codec.capture(restored), bytes);
    } finally {
      await restored.close();
    }
    expect(
      () => SnapshotCodec(categoryAware: true).canonicalize(bytes),
      throwsA(isA<InvalidSnapshot>()),
    );
  });

  test('capture refuses duplicate allocations in a damaged source schema', () async {
    final db = ProbeDatabase(
      File('${work.path}/source'),
      storageBinding: sourceBinding,
      categoryReferences: true,
    );
    try {
      // Reproduce a source whose column names survived but primary-key
      // constraints did not. Backup must reject it before a later restore fails.
      await db.customStatement(
        'CREATE TABLE broken_allocations AS SELECT * FROM allocations',
      );
      await db.customStatement('DROP TABLE allocations');
      await db.customStatement(
        'ALTER TABLE broken_allocations RENAME TO allocations',
      );
      await db.customStatement(
        'INSERT INTO allocations SELECT * FROM allocations WHERE category_id=?',
        [fixture.food.value],
      );
      await expectLater(codec.capture(db), throwsA(isA<InvalidSnapshot>()));
    } finally {
      await db.close();
    }
  });

  for (final alteration in [
    'sum',
    'version',
    'missing-category',
    'wrong-kind',
    'before-selection',
    'after-archive',
    'missing-sequence',
    'mixed-sequence',
    'receipt-version',
    'receipt-duplicate',
    'receipt-amount',
    'missing-rows',
    'module',
    'column',
    'workspace',
  ]) {
    test(
      'authenticated-looking $alteration cannot pass full reference validation',
      () async {
        final value = jsonDecode(utf8.decode(bytes)) as Map;
        final tables = value['tables'] as Map,
            rows = tables['allocations'] as List;
        final allocation = rows.first as Map;
        final receipt = (tables['receipts'] as List).firstWhere(
          (r) => r['result_id'] == expense.id.value,
        ) as Map;
        final input = jsonDecode(receipt['input'] as String) as List;
        switch (alteration) {
          case 'sum':
            allocation['amount'] = '601';
          case 'version':
            allocation['category_version'] = '2';
          case 'missing-category':
            allocation['category_id'] = PublicId.generate().value;
          case 'wrong-kind':
            allocation['category_id'] = fixture.salary.value;
          case 'before-selection':
            for (final r in rows.where(
              (r) => r['event_id'] == expense.id.value,
            )) {
              r['category_sequence'] = '1';
            }
          case 'after-archive':
            for (final r in rows.where(
              (r) => r['event_id'] == expense.id.value,
            )) {
              r['category_sequence'] = '6';
              r['category_version'] = r['category_id'] == fixture.food.value
                  ? '3'
                  : '2';
            }
          case 'missing-sequence':
            for (final r in rows.where(
              (r) => r['event_id'] == expense.id.value,
            )) {
              r['category_sequence'] = '999';
            }
          case 'mixed-sequence':
            allocation['category_sequence'] = '4';
          case 'receipt-version':
            input[4][0][1] = 99;
            receipt['input'] = jsonEncode(input);
          case 'receipt-duplicate':
            input[4][1] = input[4][0];
            receipt['input'] = jsonEncode(input);
          case 'receipt-amount':
            input[4][0][2] = fixture.money('7').toJson();
            receipt['input'] = jsonEncode(input);
          case 'missing-rows':
            rows.clear();
          case 'module':
            value['modules']['ledger'] = 99;
          case 'column':
            allocation['unknown'] = 'x';
          case 'workspace':
            allocation['workspace'] = WorkspaceId(PublicId.generate())
                .toString();
        }
        final original = File('${work.path}/source').readAsBytesSync();
        await expectLater(
          stage(utf8.encode(jsonEncode(value)), 'bad'),
          alteration == 'workspace'
              ? throwsA(isA<SqliteException>())
              : throwsA(isA<InvalidSnapshot>()),
        );
        expect(File('${work.path}/source').readAsBytesSync(), original);
      },
    );
  }

  test('schema 4 converts only known empty allocation tables without inventing versions', () async {
    final legacy = ProbeDatabase(
      File('${work.path}/old'),
      storageBinding: allocationBinding(),
      categoryAware: true,
    );
    late List<int> old;
    try {
      final fixture = AllocationFixture(legacy);
      await fixture.initialize();
      old = await SnapshotCodec(categoryAware: true).capture(legacy);
    } finally {
      await legacy.close();
    }
    await stage(old, 'converted');
    final expected = jsonDecode(utf8.decode(codec.canonicalize(old))) as Map;
    expect(expected['tables']['categories'], hasLength(3));
    expect(expected['tables']['allocations'], isEmpty);
    final forged = jsonDecode(utf8.decode(old)) as Map;
    forged['tables']['allocations'] = [
      {
        'workspace': fixture.ws.toString(),
        'event_id': expense.id.value,
        'category_id': fixture.food.value,
        'amount': '1000',
      },
    ];
    expect(
      () => codec.canonicalize(utf8.encode(jsonEncode(forged))),
      throwsA(isA<InvalidSnapshot>()),
    );
  });

  test('allocation table stage failure and in-place readers leave source unchanged', () async {
    final original = File('${work.path}/source').readAsBytesSync();
    await expectLater(
      stage(
        bytes,
        'interrupted',
        checkpoint: (point) {
          if (point == 'table:allocations') throw StateError('injected');
        },
      ),
      throwsStateError,
    );
    expect(File('${work.path}/source').readAsBytesSync(), original);
    final oldReader = ProbeDatabase(
      File('${work.path}/source'),
      storageBinding: allocationBinding(),
      categoryAware: true,
    );
    try {
      await expectLater(
        oldReader.customSelect('SELECT * FROM events').get(),
        throwsStateError,
      );
    } finally {
      await oldReader.close();
    }
    expect(File('${work.path}/source').readAsBytesSync(), original);
  });
}
