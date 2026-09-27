import 'dart:convert';
import 'dart:io';

import 'package:categories/categories.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:ledger_generation_probe/ledger_store.dart';
import 'package:modular_persistence_probe/operations.dart';
import 'package:test/test.dart';
import 'package:validated_restore_probe/snapshot.dart';

import 'support/reference_fixture.dart';

void main() {
  final root = Directory('.dart_tool/reference-session-tests')
    ..createSync(recursive: true);
  late ReferenceFixture f;
  setUp(() async {
    f = ReferenceFixture(root.createTempSync('case-'));
    await f.initialize();
    await f.upgrade();
  });
  tearDown(() => removeReferenceFixture(root, f.directory));

  test('session reads immutable historical references after rename merge and archive', () async {
    final expense = f.expense(), income = f.income();
    await f.store().withSession((s) async {
      expect(await s.allocations(f.workspace, f.priorIncome.id), isEmpty);
      await s.post(income);
      await s.post(expense);
      final rows = await s.allocations(f.workspace, expense.id);
      expect(
        rows.map((r) => r.amount.minorUnits).reduce((a, b) => a + b),
        BigInt.from(1000),
      );
      expect(rows.map((r) => r.categoryVersion), everyElement(1));
      expect(rows.map((r) => r.categorySequence), everyElement(3));
      expect(() => rows.clear(), throwsUnsupportedError);
      await s.renameCategory(f.operation(), f.food, 1, '飲食更新');
      await s.mergeCategory(
        f.operation(),
        sourceId: f.food,
        expectedSourceVersion: 2,
        targetId: f.travel,
        expectedTargetVersion: 1,
      );
      await s.archiveCategory(f.operation(), f.travel, 1, archived: true);
      expect(
        (await s.categories(f.workspace)).resolve(f.food).archived,
        isTrue,
      );
      final later = await s.allocations(f.workspace, expense.id);
      expect(later.map((r) => r.categoryId), rows.map((r) => r.categoryId));
      expect(later.map((r) => r.categoryVersion), everyElement(1));
      expect(later.map((r) => r.categorySequence), everyElement(3));
      expect((await s.post(expense)).replayed, isTrue);
      expect((await s.accounts(f.workspace)).single.balance, f.money('130'));
      expect(
        await s.snapshot(),
        validateSessionCapacity(await s.snapshot(), categoryReferences: true),
      );
    });
    expect(
      await f.store().withSession((s) => s.snapshot()),
      await f.store().snapshot(),
    );
  });

  test(
    'read scope refuses wrong workspace, missing event and revoked session',
    () async {
      final expense = f.expense();
      late LedgerSession escaped;
      await f.store().withSession((s) async {
        escaped = s;
        await s.post(expense);
        await expectLater(
          s.allocations(WorkspaceId(PublicId.generate()), expense.id),
          throwsStateError,
        );
        await expectLater(
          s.allocations(f.workspace, PublicId.generate()),
          throwsStateError,
        );
        expect(await s.allocations(f.workspace, expense.id), hasLength(2));
      });
      await expectLater(
        escaped.allocations(f.workspace, expense.id),
        throwsA(isA<SessionClosed>()),
      );
    },
  );

  test(
    'serialized retries retain one financial and allocation result',
    () async {
      final expense = f.expense();
      await f.store().withSession((s) async {
        final results = await Future.wait(
          List.generate(20, (_) => s.post(expense)),
        );
        expect(results.where((r) => !r.replayed), hasLength(1));
        final saved = await s.snapshot();
        expect(referenceTables(saved)['allocations'], hasLength(2));
        await expectLater(
          s.post(
            f.expense(
              op: expense.operation,
              allocations: [
                Allocation(f.food, f.money('10'), expectedCategoryVersion: 1),
              ],
            ),
          ),
          throwsA(isA<OperationConflict>()),
        );
        expect(await s.snapshot(), saved);
      });
    },
  );

  test('oversized receipt rolls back event rows and capacity deltas without poisoning queue', () async {
    await f.store().withSession((s) async {
      final ids = <PublicId>[];
      for (var i = 0; i < 64; i++) {
        final id = PublicId.generate();
        ids.add(id);
        await s.createCategory(
          f.operation(),
          id,
          '分攤 $i',
          CategoryKind.expense,
        );
      }
      final excessive = f.expense(
        allocations: [
          for (var i = 0; i < ids.length; i++)
            Allocation(
              ids[i],
              f.money(i == 63 ? '3.70' : '0.10'),
              expectedCategoryVersion: 1,
            ),
        ],
      );
      final before = await s.snapshot();
      for (var i = 0; i < 20; i++) {
        await expectLater(s.post(excessive), throwsA(isA<PreviewCapacity>()));
      }
      expect(await s.snapshot(), before);
      // Account for category-row updates as deltas, with escaping and UTF-8.
      await s.renameCategory(f.operation(), f.food, 1, '"' * 100);
      await s.renameCategory(f.operation(), f.food, 2, '財' * 100);
      await s.renameCategory(f.operation(), f.food, 3, '餐飲');
      await expectLater(
        s.renameCategory(f.operation(), f.food, 99, '過期'),
        throwsA(isA<CategoryException>()),
      );
      await s.post(
        f.expense(
          allocations: [
            Allocation(f.food, f.money('10'), expectedCategoryVersion: 4),
          ],
        ),
      );
      await s.post(f.income());
      expect((await s.accounts(f.workspace)).single.balance, f.money('130'));
      validateSessionCapacity(await s.snapshot(), categoryReferences: true);
    });
  });

  test('new empty reference store accepts session writes and old readers reject new format', () async {
    final fresh = f.target('empty');
    await fresh.initialize(newOperation());
    final empty = await fresh.snapshot();
    expect(jsonDecode(utf8.decode(empty))['schema'], 5);
    await expectLater(
      f
          .store(references: false)
          .restore(
            (await fresh.backup(referencePassword)).envelope,
            newOperation(),
            password: referencePassword,
          ),
      throwsA(isA<InvalidSnapshot>()),
    );
    await fresh.withSession((s) async {
      await s.createCategory(
        f.operation(),
        f.food,
        '新分類',
        CategoryKind.expense,
      );
      expect(await s.workspaces(), [f.workspace]);
      validateSessionCapacity(await s.snapshot(), categoryReferences: true);
    });
  });

  test('capacity admission counts allocations across tables and encoded bytes', () async {
    await f.store().withSession((s) => s.post(f.expense()));
    final snapshot = await f.store().snapshot();
    expect(
      validateSessionCapacity(snapshot, categoryReferences: true),
      snapshot,
    );
    expect(
      () => validateSessionCapacity(snapshot, categoryAware: true),
      throwsA(isA<InvalidSnapshot>()),
    );
    // Admission is a size/subset check; semantic validity is owned by staging.
    final rootValue = jsonDecode(utf8.decode(snapshot)) as Map;
    final tables = rootValue['tables'] as Map;
    final allocation = (tables['allocations'] as List).first;
    tables['allocations'] = List.filled(SnapshotCodec.maxRows, allocation);
    expect(
      () => validateSessionCapacity(
        utf8.encode(jsonEncode(rootValue)),
        categoryReferences: true,
      ),
      throwsA(isA<InvalidSnapshot>()),
    );
    tables['allocations'] = [allocation];
    (tables['receipts'] as List).last['input'] = jsonEncode(['x' * 1100]);
    expect(
      () => validateSessionCapacity(
        utf8.encode(jsonEncode(rootValue)),
        categoryReferences: true,
      ),
      throwsA(isA<PreviewCapacity>()),
    );
  });
}
