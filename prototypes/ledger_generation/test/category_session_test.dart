import 'dart:convert';
import 'dart:io';

import 'package:accounts/accounts.dart';
import 'package:backup_envelope_probe/envelope.dart';
import 'package:categories/categories.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:ledger_generation_probe/ledger_store.dart';
import 'package:modular_persistence_probe/operations.dart';
import 'package:storage_generation_probe/fixture_catalog_protection.dart';
import 'package:storage_generation_probe/fixture_key_slots.dart';
import 'package:test/test.dart';

final ws = WorkspaceId.parse('019f0000-0000-7000-8000-000000000000');
final other = WorkspaceId.parse('019f0000-0000-7000-8000-000000000099');
OperationId op() => OperationId(PublicId.generate());
OperationKey key([WorkspaceId? workspace]) =>
    OperationKey(workspace ?? ws, op());
const password = 'synthetic-category-session-only';
Map tables(List<int> bytes) =>
    (jsonDecode(utf8.decode(bytes)) as Map)['tables'] as Map;

Account account([String name = '日常帳戶']) => Account.open(
  id: PublicId.generate(),
  workspace: ws,
  name: name,
  kind: AccountKind.cash,
  currency: Currency('TWD', 2),
  openedOn: BusinessDate(2026, 1, 1),
);
Posting opening(Account a, {OperationKey? operation}) => Posting.opening(
  id: PublicId.generate(),
  operation: operation ?? key(),
  date: a.openedOn,
  account: PostingAccount(
    id: a.id,
    workspace: ws,
    currency: a.currency,
    expectedVersion: a.version,
  ),
  amount: Money.parse(a.currency, '100'),
);

void main() {
  final root = Directory('.dart_tool/category-session-tests')
    ..createSync(recursive: true);
  late Directory directory;
  late LedgerStore store;
  LedgerStore makeStore(String name, {bool categories = true}) {
    final slots = FixtureKeySlots(Directory('${directory.path}/$name-keys'));
    return LedgerStore(
      Directory('${directory.path}/$name'),
      slots,
      catalogProtection: fixtureCatalogProtection(slots),
      categoryAware: categories,
    );
  }

  setUp(() async {
    directory = root.createTempSync('case-');
    store = makeStore('store');
    await store.initialize(op());
  });
  tearDown(() {
    if (!directory.absolute.path.startsWith(
      '${root.absolute.path}${Platform.pathSeparator}',
    )) {
      throw StateError('Unsafe cleanup');
    }
    directory.deleteSync(recursive: true);
  });

  test(
    'all commands preserve history and category-only workspace discovery',
    () async {
      final parent = PublicId.generate(),
          child = PublicId.generate(),
          target = PublicId.generate();
      await store.withSession((s) async {
        expect(await s.workspaces(), isEmpty);
        await s.createCategory(key(), parent, '生活', CategoryKind.expense);
        await s.createCategory(
          key(),
          child,
          '早餐',
          CategoryKind.expense,
          parentId: parent,
        );
        final original = await s.categories(ws);
        await s.renameCategory(key(), child, 1, '餐飲');
        await s.moveCategory(key(), child, 2, null);
        await s.archiveCategory(key(), parent, 1, archived: true);
        await s.archiveCategory(key(), parent, 2, archived: false);
        await s.createCategory(key(), target, '飲食', CategoryKind.expense);
        await s.mergeCategory(
          key(),
          sourceId: child,
          expectedSourceVersion: 3,
          targetId: target,
          expectedTargetVersion: 1,
        );
        final catalog = await s.categories(ws);
        expect(original.get(child).name, '早餐');
        expect(catalog.get(child).replacementId, target);
        expect(catalog.resolve(child).name, '飲食');
        expect(catalog.get(parent).version, 3);
        expect(await s.accounts(ws), isEmpty);
        expect(await s.workspaces(), [ws]);
        final saved = tables(await s.snapshot());
        expect(saved['categories'], hasLength(3));
        expect(saved['category_changes'], hasLength(8));
        expect(saved['receipts'], hasLength(8));
        expect(saved['audit'], hasLength(8));
      });
      final saved = await store.snapshot();
      expect(await store.withSession((s) => s.snapshot()), saved);
    },
  );

  test(
    'legacy sessions refuse categories without changing the financial store',
    () async {
      final legacy = makeStore('legacy', categories: false);
      await legacy.initialize(op());
      final before = await legacy.snapshot();
      await legacy.withSession((s) async {
        await expectLater(s.categories(ws), throwsUnsupportedError);
        await expectLater(
          s.createCategory(
            key(),
            PublicId.generate(),
            '早餐',
            CategoryKind.expense,
          ),
          throwsUnsupportedError,
        );
        expect(await s.snapshot(), before);
      });
    },
  );

  test('duplicates serialize once; stale and invalid edits roll back without poisoning queue', () async {
    final id = PublicId.generate(), parent = PublicId.generate();
    final operation = key();
    await store.withSession((s) async {
      final results = await Future.wait(
        List.generate(
          20,
          (_) => s.createCategory(operation, id, '早餐', CategoryKind.expense),
        ),
      );
      expect(results.where((r) => !r.replayed), hasLength(1));
      await s.createCategory(key(), parent, '薪資', CategoryKind.income);
      final before = await s.snapshot();
      await expectLater(
        s.moveCategory(key(), id, 1, parent),
        throwsA(isA<CategoryException>()),
      );
      await expectLater(
        s.renameCategory(key(), id, 99, '午餐'),
        throwsA(isA<CategoryException>()),
      );
      await expectLater(
        s.createCategory(operation, id, '不同內容', CategoryKind.expense),
        throwsA(isA<OperationConflict>()),
      );
      expect(await s.snapshot(), before);
      await s.renameCategory(key(), id, 1, '午餐');
      expect((await s.categories(ws)).get(id).version, 2);
    });
  });

  test('revoked facade rejects reads and writes after draining queued commands on failure', () async {
    late LedgerSession escaped;
    late Future<CommitResult> pending;
    final id = PublicId.generate();
    await expectLater(
      store.withSession<void>((s) async {
        escaped = s;
        pending = s.createCategory(key(), id, '早餐', CategoryKind.expense);
        throw const FormatException('caller');
      }),
      throwsFormatException,
    );
    expect((await pending).replayed, isFalse);
    await expectLater(escaped.categories(ws), throwsA(isA<SessionClosed>()));
    await expectLater(
      escaped.renameCategory(key(), id, 1, '午餐'),
      throwsA(isA<SessionClosed>()),
    );
    expect(
      (await store.withSession((s) => s.categories(ws))).get(id).name,
      '早餐',
    );
  });

  test(
    'workspace isolation and shared financial/metadata operation namespace',
    () async {
      final id = PublicId.generate(), operation = key();
      final a = account();
      await store.withSession((s) async {
        await s.createCategory(operation, id, '早餐', CategoryKind.expense);
        await s.createCategory(
          OperationKey(other, operation.operation),
          id,
          '薪資',
          CategoryKind.income,
        );
        final before = await s.snapshot();
        await expectLater(
          s.createAccount(a, opening(a, operation: operation)),
          throwsA(isA<OperationConflict>()),
        );
        expect(await s.snapshot(), before);
        final initial = opening(a);
        await s.createAccount(a, initial);
        await expectLater(
          s.createCategory(
            initial.operation,
            PublicId.generate(),
            '薪資',
            CategoryKind.income,
          ),
          throwsA(isA<OperationConflict>()),
        );
        expect((await s.categories(ws)).get(id).kind, CategoryKind.expense);
        expect((await s.categories(other)).get(id).kind, CategoryKind.income);
        expect(await s.workspaces(), [ws, other]);
        expect(
          (await s.accounts(ws)).single.balance.minorUnits,
          BigInt.from(10000),
        );
      });
    },
  );

  test('bounded category history remains exportable and replayable at both limits', () async {
    final first = PublicId.generate(), firstOperation = key();
    final timer = Stopwatch()..start();
    await store.withSession((s) async {
      await s.createCategory(firstOperation, first, '早餐', CategoryKind.expense);
      // Counts cover the entire store, not only the current workspace.
      for (var i = 1; i < LedgerSession.maxCategories; i++) {
        await s.createCategory(
          key(i.isEven ? ws : other),
          PublicId.generate(),
          '分類 $i',
          CategoryKind.expense,
        );
      }
      final before = await s.snapshot();
      await expectLater(
        s.createCategory(
          key(),
          PublicId.generate(),
          '超額',
          CategoryKind.expense,
        ),
        throwsA(isA<PreviewCapacity>()),
      );
      expect(await s.snapshot(), before);
      for (
        var i = 0;
        i < LedgerSession.maxCategoryChanges - LedgerSession.maxCategories;
        i++
      ) {
        await s.renameCategory(key(), first, i + 1, '早餐 $i');
      }
      final full = await s.snapshot();
      expect(
        (await s.createCategory(
          firstOperation,
          first,
          '早餐',
          CategoryKind.expense,
        )).replayed,
        isTrue,
      );
      await expectLater(
        s.createCategory(firstOperation, first, '衝突', CategoryKind.expense),
        throwsA(isA<OperationConflict>()),
      );
      await expectLater(
        s.renameCategory(key(), first, 769, '超額'),
        throwsA(isA<PreviewCapacity>()),
      );
      expect(await s.snapshot(), full);
      // Financial writes still have their separate allowance.
      final a = account();
      await s.createAccount(a, opening(a));
    });
    final bytes = await store.snapshot();
    expect(validateSessionCapacity(bytes, categoryAware: true), bytes);
    final backup = await store.backup(password);
    final restored = makeStore('capacity-restore');
    await restored.restore(
      backup.envelope,
      op(),
      recoveryKey: backup.recoveryKey,
    );
    expect(await restored.snapshot(), bytes);
    await restored.withSession((s) async {
      expect(
        (await s.createCategory(
          firstOperation,
          first,
          '早餐',
          CategoryKind.expense,
        )).replayed,
        isTrue,
      );
      await expectLater(
        s.createCategory(
          key(other),
          PublicId.generate(),
          '超額',
          CategoryKind.expense,
        ),
        throwsA(isA<PreviewCapacity>()),
      );
    });
    print(
      'category capacity: ${bytes.length} bytes, ${timer.elapsedMilliseconds} ms; 256 categories, 1024 changes',
    );
  }, timeout: const Timeout(Duration(minutes: 4)));

  test('escaped maximum-length names survive password and recovery restores independently', () async {
    final names = ['"' * 100, r'\' * 100, '財' * 100, '🍜' * 50];
    final operations = <OperationKey>[], ids = <PublicId>[];
    await store.withSession((s) async {
      for (final name in names) {
        final a = account(name);
        await s.createAccount(a, opening(a));
        final operation = key(), id = PublicId.generate();
        operations.add(operation);
        ids.add(id);
        await s.createCategory(operation, id, name, CategoryKind.expense);
      }
    });
    final bytes = await store.snapshot();
    expect(validateSessionCapacity(bytes, categoryAware: true), bytes);
    final backup = await store.backup(password);
    for (final recovery in [false, true]) {
      final restored = makeStore('restore-$recovery');
      await restored.restore(
        backup.envelope,
        op(),
        password: recovery ? null : password,
        recoveryKey: recovery ? backup.recoveryKey : null,
      );
      expect(await restored.snapshot(), bytes);
      await restored.withSession((s) async {
        for (var i = 0; i < names.length; i++) {
          expect((await s.categories(ws)).get(ids[i]).name, names[i]);
          expect(
            (await s.createCategory(
              operations[i],
              ids[i],
              names[i],
              CategoryKind.expense,
            )).replayed,
            isTrue,
          );
        }
        expect(
          (await s.accounts(ws)).map((a) => a.balance.minorUnits),
          everyElement(BigInt.from(10000)),
        );
      });
    }
  });

  test('oversized valid imported audit data permits read/replay but blocks new mutations', () async {
    final id = PublicId.generate(), operation = key();
    await store.withSession(
      (s) => s.createCategory(operation, id, '早餐', CategoryKind.expense),
    );
    final payload = jsonDecode(utf8.decode(await store.snapshot())) as Map;
    // Whitespace in command JSON is semantically harmless but consumes bytes.
    final receipt = (payload['tables']['receipts'] as List).single as Map;
    receipt['input'] = '${' ' * 2000}${receipt['input']}';
    final portable = utf8.encode(jsonEncode(payload));
    final imported = makeStore('oversized');
    final backup = await EnvelopeCodec().create(portable, password: password);
    await imported.restore(backup.envelope, op(), password: password);
    final before = await imported.snapshot();
    await imported.withSession((s) async {
      expect((await s.categories(ws)).get(id).name, '早餐');
      // Existing receipt equality is byte-exact, so changed whitespace remains
      // a conflict (not a capacity error); capacity cannot hide that distinction.
      await expectLater(
        s.createCategory(operation, id, '早餐', CategoryKind.expense),
        throwsA(isA<OperationConflict>()),
      );
      await expectLater(
        s.renameCategory(key(), id, 1, '午餐'),
        throwsA(isA<PreviewCapacity>()),
      );
      final a = account();
      await expectLater(
        s.createAccount(a, opening(a)),
        throwsA(isA<PreviewCapacity>()),
      );
      expect(await s.snapshot(), before);
    });
    expect(
      await EnvelopeCodec().openWithPassword(
        (await imported.backup(password)).envelope,
        password,
      ),
      before,
    );
  });
}
