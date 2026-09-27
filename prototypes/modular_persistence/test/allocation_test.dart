import 'dart:io';

import 'package:categories/categories.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:modular_persistence_probe/allocation_validation.dart';
import 'package:modular_persistence_probe/categories_adapter.dart';
import 'package:modular_persistence_probe/database.dart';
import 'package:modular_persistence_probe/workflows.dart';
import 'package:test/test.dart';

import 'package:modular_persistence_probe/fixture_allocation.dart';

void main() {
  final root = Directory('.dart_tool/allocation-tests')
    ..createSync(recursive: true);
  late Directory work;
  late ProbeDatabase db;
  late AllocationFixture fixture;
  setUp(() async {
    work = root.createTempSync('case-');
    db = ProbeDatabase(
      File('${work.path}/db'),
      storageBinding: allocationBinding(),
      categoryReferences: true,
    );
    fixture = AllocationFixture(db);
    await fixture.initialize();
  });
  tearDown(() async {
    await db.close();
    if (!work.absolute.path.startsWith(
      '${root.absolute.path}${Platform.pathSeparator}',
    ))
      throw StateError('Unsafe cleanup');
    work.deleteSync(recursive: true);
  });

  test(
    'income and split expense retain one cash effect with versioned references',
    () async {
      final workflow = FinancialWorkflows(db);
      final expense = fixture.expense(
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
      await workflow.post(expense);
      await workflow.post(fixture.income());
      expect(
        await workflow.ledger.balance(fixture.reference),
        fixture.money('110'),
      );
      final rows = await db.customSelect('SELECT * FROM allocations').get();
      expect(rows, hasLength(3));
      expect(rows.map((r) => r.read<int>('category_version')), everyElement(1));
      expect(
        rows.map((r) => r.read<int>('category_sequence')),
        everyElement(3),
      );
      expect(await validateAllocationHistory(db), hasLength(3));
    },
  );

  test('later rename merge and archive preserve old posting replay and original IDs', () async {
    final workflow = FinancialWorkflows(db), adapter = CategoriesAdapter(db);
    final posting = fixture.expense();
    final results = await Future.wait(
      List.generate(20, (_) => workflow.post(posting)),
    );
    expect(results.where((r) => !r.replayed), hasLength(1));
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
    final before = await allocationState(db);
    expect((await workflow.post(posting)).replayed, isTrue);
    await expectLater(
      workflow.post(fixture.expense(version: 3, op: posting.operation)),
      throwsA(isA<OperationConflict>()),
    );
    await expectLater(
      workflow.post(fixture.expense(version: 3)),
      throwsA(isA<CategoryException>()),
    );
    expect(await allocationState(db), before);
    expect(await validateAllocationHistory(db), hasLength(6));
    expect(
      (await db.customSelect('SELECT category_id FROM allocations').getSingle())
          .read<String>('category_id'),
      fixture.food.value,
    );
  });

  test('missing stale wrong-kind and unversioned selections leave no financial or audit writes', () async {
    final before = await allocationState(db);
    final proposals = [
      fixture.expense(version: null),
      fixture.expense(version: 2),
      fixture.expense(
        allocations: [
          Allocation(
            PublicId.generate(),
            fixture.money('10'),
            expectedCategoryVersion: 1,
          ),
        ],
      ),
      fixture.expense(
        allocations: [
          Allocation(
            fixture.salary,
            fixture.money('10'),
            expectedCategoryVersion: 1,
          ),
        ],
      ),
    ];
    for (final proposal in proposals) {
      await expectLater(
        FinancialWorkflows(db).post(proposal),
        throwsA(anyOf(isA<ArgumentError>(), isA<CategoryException>())),
      );
      expect(await allocationState(db), before);
    }
    final foreign = WorkspaceId(PublicId.generate()), id = PublicId.generate();
    await CategoriesAdapter(db).mutate(
      OperationKey(foreign, OperationId(PublicId.generate())),
      CategoryMutation.create(id, '外部', CategoryKind.expense),
    );
    final afterForeign = await allocationState(db);
    await expectLater(
      FinancialWorkflows(db).post(
        fixture.expense(
          allocations: [
            Allocation(id, fixture.money('10'), expectedCategoryVersion: 1),
          ],
        ),
      ),
      throwsA(isA<CategoryException>()),
    );
    expect(await allocationState(db), afterForeign);
  });

  test('competing category revisions and postings have one serial financial result', () async {
    var successful = 0;
    final workflow = FinancialWorkflows(db), adapter = CategoriesAdapter(db);
    for (var i = 0; i < 20; i++) {
      final proposal = fixture.expense(version: i + 1);
      Future<Object> post() => workflow
          .post(proposal)
          .then<Object>(
            (result) => result,
            onError: (Object error) {
              if (error is CategoryException) return error;
              throw error;
            },
          );
      Future<Object> rename() => adapter.mutate(
        fixture.operation(),
        CategoryMutation.rename(fixture.food, i + 1, '修訂 $i'),
      );
      final results = await Future.wait(
        i.isEven ? [post(), rename()] : [rename(), post()],
      );
      final result = results[i.isEven ? 0 : 1];
      if (result is CommitResult) {
        successful++;
      } else {
        expect(
          (result as CategoryException).code,
          CategoryError.versionConflict,
        );
      }
    }
    expect(
      (await workflow.ledger.balance(fixture.reference)).minorUnits,
      BigInt.from(10000 - successful * 1000),
    );
    expect(await validateAllocationHistory(db), hasLength(23));
  });

  for (final point in ['event', 'leg', 'allocation', 'receipt', 'audit']) {
    test(
      'failure at $point rolls back attribution money receipt and audit together',
      () async {
        final before = await allocationState(db), posting = fixture.expense();
        await expectLater(
          FinancialWorkflows(db).post(
            posting,
            checkpoint: (at) {
              if (at == point) throw StateError('injected');
            },
          ),
          throwsStateError,
        );
        expect(await allocationState(db), before);
        expect((await FinancialWorkflows(db).post(posting)).replayed, isFalse);
        expect(
          await FinancialWorkflows(db).ledger.balance(fixture.reference),
          fixture.money('90'),
        );
      },
    );
  }

  test(
    'schema 4 retains refusal instead of accepting unverifiable references',
    () async {
      final legacy = ProbeDatabase(
        File('${work.path}/legacy'),
        storageBinding: allocationBinding(),
        categoryAware: true,
      );
      try {
        final old = AllocationFixture(legacy);
        await old.initialize();
        final before = await allocationState(legacy);
        await expectLater(
          FinancialWorkflows(legacy).post(old.expense()),
          throwsUnsupportedError,
        );
        expect(await allocationState(legacy), before);
      } finally {
        await legacy.close();
      }
    },
  );
}
