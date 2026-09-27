import 'dart:convert';
import 'dart:io';

import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:modular_persistence_probe/database.dart';
import 'package:modular_persistence_probe/fixture_allocation.dart';
import 'package:modular_persistence_probe/merchants_adapter.dart';
import 'package:modular_persistence_probe/tags_adapter.dart';
import 'package:modular_persistence_probe/workflows.dart';
import 'package:test/test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:validated_restore_probe/snapshot.dart';

void main() {
  final root = Directory('.dart_tool/merchants-tests')
    ..createSync(recursive: true);
  final codec = SnapshotCodec(merchantsAware: true);
  late Directory work;
  late ProbeDatabase db;
  late AllocationFixture f;
  late PublicId first, second;
  late Posting posting;
  late MerchantSelection selection;
  late List<TagSelection> tags;
  setUp(() async {
    work = root.createTempSync('case-');
    db = ProbeDatabase(
      File('${work.path}/source'),
      storageBinding: allocationBinding(),
      merchantsAware: true,
    );
    f = AllocationFixture(db);
    await f.initialize();
    first = PublicId.generate();
    second = PublicId.generate();
    await MerchantsAdapter(db)
        .mutate(f.operation(), MerchantMutation.create(first, '出差'));
    await MerchantsAdapter(db)
        .mutate(f.operation(), MerchantMutation.create(second, '旅行'));
    posting = f.expense();
    selection = MerchantSelection(first, 1);
    final tag = PublicId.generate();
    await TagsAdapter(db).mutate(f.operation(), TagMutation.create(tag, '情境'));
    tags = [TagSelection(tag, 1)];
  });
  tearDown(() async {
    await db.close();
    if (!work.resolveSymbolicLinksSync().startsWith(
      '${root.resolveSymbolicLinksSync()}${Platform.pathSeparator}',
    ))
      throw StateError('Unsafe cleanup');
    work.deleteSync(recursive: true);
  });
  Future<void> stage(List<int> bytes) => codec.stage(
    bytes,
    File('${work.path}/stage-${PublicId.generate().value}'),
    openDatabase: (file) => ProbeDatabase(
      file,
      storageBinding: allocationBinding(),
      merchantsAware: true,
    ),
  );
  test('combined classifications and merchants round-trip after rename merge archive and replay', () async {
    await FinancialWorkflows(db).post(posting, merchant: selection, tags: tags);
    await MerchantsAdapter(db)
        .mutate(f.operation(), MerchantMutation.rename(first, 1, '差旅'));
    await MerchantsAdapter(db)
        .mutate(f.operation(), MerchantMutation.merge(first, 2, second, 1));
    await MerchantsAdapter(db)
        .mutate(f.operation(), MerchantMutation.archive(second, 1, true));
    final before = await codec.capture(db);
    expect(
      (await FinancialWorkflows(
        db,
      ).post(posting, merchant: selection, tags: tags)).replayed,
      isTrue,
    );
    expect(await codec.capture(db), before);
    await stage(before);
    expect(
      await FinancialWorkflows(db).ledger.balance(f.reference),
      f.money('90'),
    );
    await expectLater(
      FinancialWorkflows(db)
          .post(posting, merchant: MerchantSelection(second, 1), tags: tags),
      throwsA(isA<OperationConflict>()),
    );
    expect(
      () => SnapshotCodec(tagsAware: true).canonicalize(before),
      throwsA(isA<InvalidSnapshot>()),
    );
  });
  test('stale missing duplicate and cross-workspace merchants reject the entire financial write', () async {
    final before = await codec.capture(db);
    for (final merchant in [
      MerchantSelection(first, 2),
      MerchantSelection(PublicId.generate(), 1),
    ]) {
      await expectLater(
        Future.sync(
          () =>
              FinancialWorkflows(db)
                  .post(posting, merchant: merchant, tags: tags),
        ),
        throwsException,
      );
      expect(await codec.capture(db), before);
    }
    final foreign = OperationKey(
      WorkspaceId(PublicId.generate()),
      OperationId(PublicId.generate()),
    );
    final merchant = PublicId.generate();
    await MerchantsAdapter(db)
        .mutate(foreign, MerchantMutation.create(merchant, '別的帳本'));
    final current = await codec.capture(db);
    await expectLater(
      FinancialWorkflows(db)
          .post(posting, merchant: MerchantSelection(merchant, 1), tags: tags),
      throwsException,
    );
    expect(await codec.capture(db), current);
  });
  for (final point in ['merchant', 'merchant-history', 'receipt', 'audit']) {
    test('metadata failure at $point is atomic and can retry', () async {
      final before = await codec.capture(db),
          operation = f.operation(),
          mutation = MerchantMutation.rename(first, 1, 'changed');
      await expectLater(
        MerchantsAdapter(db).mutate(
          operation,
          mutation,
          checkpoint: (p) {
            if (p == point) throw StateError('injected');
          },
        ),
        throwsStateError,
      );
      expect(await codec.capture(db), before);
      expect(
        (await MerchantsAdapter(db).mutate(operation, mutation)).replayed,
        isFalse,
      );
      await codec.capture(db);
    });
  }
  for (final point in ['merchant', 'receipt', 'audit']) {
    test(
      'merchant posting failure at $point rolls back amounts references and audit',
      () async {
        final before = await codec.capture(db);
        await expectLater(
          FinancialWorkflows(db).post(
            posting,
            merchant: selection,
            tags: tags,
            checkpoint: (p) {
              if (p == point) throw StateError('injected');
            },
          ),
          throwsStateError,
        );
        expect(await codec.capture(db), before);
        await FinancialWorkflows(db)
            .post(posting, merchant: selection, tags: tags);
        await codec.capture(db);
      },
    );
  }
  for (final change in [
    'missing-merchant',
    'version',
    'before-selection',
    'after-archive',
    'missing-row',
    'duplicate-row',
    'missing-receipt',
    'wrapper',
    'duplicate-selection',
    'history',
    'unknown-module',
  ]) {
    test(
      'restore rejects tampered $change without changing live source',
      () async {
        await FinancialWorkflows(db)
            .post(posting, merchant: selection, tags: tags);
        await MerchantsAdapter(db)
            .mutate(f.operation(), MerchantMutation.archive(first, 1, true));
        final before = await codec.capture(db);
        final root = jsonDecode(utf8.decode(before)) as Map;
        final tables = root['tables'] as Map;
        final rows = tables['event_merchants'] as List;
        final row = rows.first as Map;
        final receipts = tables['receipts'] as List;
        final receipt = receipts.cast<Map>().firstWhere(
          (r) => r['result_id'] == posting.id.value,
        );
        final input = jsonDecode(receipt['input'] as String) as List;
        switch (change) {
          case 'missing-merchant':
            row['merchant_id'] = PublicId.generate().value;
          case 'version':
            row['merchant_version'] = '999';
          case 'before-selection':
            row['merchant_sequence'] = '0';
          case 'after-archive':
            for (final r in rows) {
              r['merchant_sequence'] = '3';
            }
          case 'missing-row':
            rows.removeLast();
          case 'duplicate-row':
            rows.add(Map.of(row));
          case 'missing-receipt':
            receipts.remove(receipt);
          case 'wrapper':
            receipt['input'] = jsonEncode(input[1]);
          case 'duplicate-selection':
            (input[2] as List).add(input[2][0]);
            receipt['input'] = jsonEncode(input);
          case 'history':
            (tables['merchant_changes'] as List).removeAt(0);
          case 'unknown-module':
            root['modules']['merchants'] = 2;
        }
        await expectLater(
          stage(utf8.encode(jsonEncode(root))),
          throwsA(anyOf(isA<InvalidSnapshot>(), isA<SqliteException>())),
        );
        expect(await codec.capture(db), before);
      },
    );
  }
  test('backup refuses duplicate merchant references if source constraints were lost', () async {
    await FinancialWorkflows(db).post(posting, merchant: selection, tags: tags);
    await db.customStatement(
      'CREATE TABLE broken_merchants AS SELECT * FROM event_merchants',
    );
    await db.customStatement('DROP TABLE event_merchants');
    await db.customStatement(
      'ALTER TABLE broken_merchants RENAME TO event_merchants',
    );
    await db.customStatement(
      'INSERT INTO event_merchants SELECT * FROM event_merchants',
    );
    await expectLater(codec.capture(db), throwsA(isA<InvalidSnapshot>()));
  });
  test(
    'alias add remove commands replay and remain in restored canonical history',
    () async {
      final adapter = MerchantsAdapter(db);
      final add = f.operation(), remove = f.operation();
      final added = MerchantMutation.alias(first, 1, 'SEVEN', remove: false);
      await adapter.mutate(add, added);
      await FinancialWorkflows(db)
          .post(posting, merchant: MerchantSelection(first, 2), tags: tags);
      await adapter.mutate(
        remove,
        MerchantMutation.alias(first, 2, 'seven', remove: true),
      );
      final before = await codec.capture(db);
      expect((await adapter.mutate(add, added)).replayed, isTrue);
      expect((await adapter.read(f.ws)).candidates('seven'), isEmpty);
      expect(await codec.capture(db), before);
      await stage(before);
      final changed = jsonDecode(utf8.decode(before)) as Map;
      final receipts = changed['tables']['receipts'] as List;
      final row = receipts.cast<Map>().firstWhere(
        (r) => r['operation_id'] == remove.operation.toString(),
      );
      final input = jsonDecode(row['input'] as String) as List;
      input[4] = 'different';
      row['input'] = jsonEncode(input);
      await expectLater(
        stage(utf8.encode(jsonEncode(changed))),
        throwsA(isA<InvalidSnapshot>()),
      );
      expect(await codec.capture(db), before);
    },
  );
}
