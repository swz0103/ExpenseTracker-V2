import 'dart:convert';
import 'dart:io';

import 'package:accounts/accounts.dart';
import 'package:categories/categories.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:modular_persistence_probe/categories_adapter.dart';
import 'package:modular_persistence_probe/database.dart';
import 'package:modular_persistence_probe/storage_binding.dart';
import 'package:modular_persistence_probe/workflows.dart';
import 'package:test/test.dart';

void main() {
  final root = Directory('.dart_tool/category-tests')
    ..createSync(recursive: true);
  final ws = WorkspaceId(PublicId.generate());
  late Directory work;
  late ProbeDatabase db;
  late StorageBinding binding;
  late CategoriesAdapter adapter;
  OperationKey op([WorkspaceId? workspace]) =>
      OperationKey(workspace ?? ws, OperationId(PublicId.generate()));
  setUp(() {
    work = root.createTempSync('case-');
    binding = StorageBinding(
      PublicId.generate(),
      PublicId.generate(),
      OperationId(PublicId.generate()),
      'a' * 64,
    );
    db = ProbeDatabase(
      File('${work.path}/db'),
      storageBinding: binding,
      categoryAware: true,
    );
    adapter = CategoriesAdapter(db);
  });
  tearDown(() async {
    await db.close();
    if (!work.resolveSymbolicLinksSync().startsWith(
      '${root.resolveSymbolicLinksSync()}${Platform.pathSeparator}',
    ))
      throw StateError('Unsafe cleanup');
    work.deleteSync(recursive: true);
  });

  test('all metadata commands persist and replay through the same domain after reopen', () async {
    final parent = PublicId.generate(),
        child = PublicId.generate(),
        target = PublicId.generate();
    final commands = [
      CategoryMutation.create(parent, '飲食', CategoryKind.expense),
      CategoryMutation.create(target, '其他', CategoryKind.expense),
      CategoryMutation.create(
        child,
        '午餐',
        CategoryKind.expense,
        parentId: parent,
      ),
      CategoryMutation.rename(child, 1, '晚餐'),
      CategoryMutation.move(child, 2, target),
      CategoryMutation.archive(child, 3, true),
      CategoryMutation.archive(child, 4, false),
      CategoryMutation.merge(child, 5, target, 1),
    ];
    for (final command in commands) {
      await adapter.mutate(op(), command);
    }
    expect((await validateCategoryHistory(db)).length, commands.length);
    await db.close();
    db = ProbeDatabase(
      File('${work.path}/db'),
      storageBinding: binding,
      categoryAware: true,
    );
    final catalog = await CategoriesAdapter(db).read(ws);
    expect(catalog.get(child).name, '晚餐');
    expect(catalog.get(child).version, 6);
    expect(catalog.resolve(child).id, target);
    expect((await validateCategoryHistory(db)).length, 8);
  });

  test(
    'retry after a later revision returns old result without rewriting history',
    () async {
      final id = PublicId.generate(), operation = op();
      final create = CategoryMutation.create(id, '原名', CategoryKind.income);
      await adapter.mutate(operation, create);
      await adapter.mutate(op(), CategoryMutation.rename(id, 1, '新名'));
      final replay = await adapter.mutate(operation, create);
      expect(replay.replayed, isTrue);
      expect(replay.id, id);
      expect((await adapter.read(ws)).get(id).name, '新名');
      expect((await validateCategoryHistory(db)).length, 2);
      await expectLater(
        adapter.mutate(
          operation,
          CategoryMutation.create(id, '改名', CategoryKind.income),
        ),
        throwsA(isA<OperationConflict>()),
      );
    },
  );

  for (final point in ['category', 'category-history', 'receipt', 'audit']) {
    test(
      'failure at $point rolls back metadata, history, receipt and audit together',
      () async {
        final operation = op(), id = PublicId.generate();
        final create = CategoryMutation.create(id, '分類', CategoryKind.expense);
        await expectLater(
          adapter.mutate(
            operation,
            create,
            checkpoint: (at) {
              if (at == point) throw StateError('injected');
            },
          ),
          throwsStateError,
        );
        for (final table in [
          'categories',
          'category_changes',
          'receipts',
          'audit',
        ]) {
          expect(
            (await db
                    .customSelect('SELECT COUNT(*) AS n FROM $table')
                    .getSingle())
                .read<int>('n'),
            0,
          );
        }
        expect((await adapter.mutate(operation, create)).replayed, isFalse);
        expect((await validateCategoryHistory(db)).length, 1);
      },
    );
  }

  test(
    'metadata and financial operations share one deduplication namespace',
    () async {
      final operation = op(), id = PublicId.generate();
      await adapter.mutate(
        operation,
        CategoryMutation.create(id, '分類', CategoryKind.expense),
      );
      final account = Account.open(
        id: PublicId.generate(),
        workspace: ws,
        name: '現金',
        kind: AccountKind.cash,
        currency: Currency('TWD', 2),
        openedOn: BusinessDate(2026, 9, 27),
      );
      final opening = Posting.opening(
        id: PublicId.generate(),
        operation: operation,
        date: account.openedOn,
        account: PostingAccount(
          id: account.id,
          workspace: ws,
          currency: account.currency,
          expectedVersion: 1,
        ),
        amount: Money.parse(account.currency, '100'),
      );
      await expectLater(
        FinancialWorkflows(db).createAccount(account, opening),
        throwsA(isA<OperationConflict>()),
      );
      expect(
        (await db
                .customSelect('SELECT COUNT(*) AS n FROM accounts')
                .getSingle())
            .read<int>('n'),
        0,
      );
      expect((await validateCategoryHistory(db)).length, 1);
    },
  );

  test(
    'workspaces can reuse IDs and operation IDs without mixing histories',
    () async {
      final id = PublicId.generate(), operation = op();
      final other = WorkspaceId(PublicId.generate());
      await adapter.mutate(
        operation,
        CategoryMutation.create(id, '支出', CategoryKind.expense),
      );
      await adapter.mutate(
        OperationKey(other, operation.operation),
        CategoryMutation.create(id, '收入', CategoryKind.income),
      );
      expect((await adapter.read(ws)).get(id).kind, CategoryKind.expense);
      expect((await adapter.read(other)).get(id).kind, CategoryKind.income);
      expect((await validateCategoryHistory(db)).length, 2);
    },
  );

  test(
    'stale version and invalid parents leave no operation receipt',
    () async {
      final id = PublicId.generate();
      await adapter.mutate(
        op(),
        CategoryMutation.create(id, '分類', CategoryKind.expense),
      );
      await expectLater(
        adapter.mutate(op(), CategoryMutation.rename(id, 0, '錯誤')),
        throwsA(isA<CategoryException>()),
      );
      await expectLater(
        adapter.mutate(op(), CategoryMutation.move(id, 1, PublicId.generate())),
        throwsA(isA<CategoryException>()),
      );
      expect((await validateCategoryHistory(db)).length, 1);
    },
  );

  test(
    'history detects a forged final state even when the tree remains legal',
    () async {
      final id = PublicId.generate();
      await adapter.mutate(
        op(),
        CategoryMutation.create(id, '原名', CategoryKind.expense),
      );
      final payload = categoryJson((await adapter.read(ws)).get(id));
      payload['name'] = '偽造';
      await db.customStatement('UPDATE categories SET payload=?', [
        jsonEncode(payload),
      ]);
      await expectLater(
        validateCategoryHistory(db),
        throwsA(isA<InvalidCategoryHistory>()),
      );
    },
  );

  test('input schema rejects unknown commands and takes an immutable copy', () {
    final input = [
      'category-v1',
      'create',
      PublicId.generate().value,
      '分類',
      'expense',
      null,
    ];
    final command = CategoryMutation.fromInput(input);
    input[3] = 'changed';
    expect(command.input[3], '分類');
    expect(() => command.input.clear(), throwsUnsupportedError);
    for (final value in [
      null,
      [],
      ['category-v2', 'create'],
      ['category-v1', 'rename', 'id', '1', 'x'],
    ]) {
      expect(
        () => CategoryMutation.fromInput(value),
        throwsA(isA<InvalidCategoryHistory>()),
      );
    }
  });

  test(
    'concurrent retries publish one category, history entry and receipt',
    () async {
      final operation = op();
      final command = CategoryMutation.create(
        PublicId.generate(),
        '分類',
        CategoryKind.expense,
      );
      final results = await Future.wait([
        adapter.mutate(operation, command),
        adapter.mutate(operation, command),
      ]);
      expect(results.where((r) => r.replayed).length, 1);
      expect(results.map((r) => r.id).toSet().length, 1);
      expect((await adapter.read(ws)).categories.length, 1);
      expect((await validateCategoryHistory(db)).length, 1);
    },
  );

  test('legacy schema cannot silently write the categories module', () async {
    await db.close();
    db = ProbeDatabase(File('${work.path}/legacy'));
    expect(
      () => CategoriesAdapter(db).mutate(
        op(),
        CategoryMutation.create(
          PublicId.generate(),
          '分類',
          CategoryKind.expense,
        ),
      ),
      throwsStateError,
    );
  });
}
