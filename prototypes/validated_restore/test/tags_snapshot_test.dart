import 'dart:convert';
import 'dart:io';

import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:modular_persistence_probe/database.dart';
import 'package:modular_persistence_probe/fixture_allocation.dart';
import 'package:modular_persistence_probe/tags_adapter.dart';
import 'package:modular_persistence_probe/workflows.dart';
import 'package:test/test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:validated_restore_probe/snapshot.dart';

void main() {
  final root = Directory('.dart_tool/tags-tests')..createSync(recursive: true);
  final codec = SnapshotCodec(tagsAware: true);
  late Directory work;
  late ProbeDatabase db;
  late AllocationFixture f;
  late PublicId first, second;
  late Posting posting;
  late List<TagSelection> selections;
  setUp(() async {
    work = root.createTempSync('case-');
    db = ProbeDatabase(
      File('${work.path}/source'),
      storageBinding: allocationBinding(),
      tagsAware: true,
    );
    f = AllocationFixture(db);
    await f.initialize();
    first = PublicId.generate();
    second = PublicId.generate();
    await TagsAdapter(db)
        .mutate(f.operation(), TagMutation.create(first, '出差'));
    await TagsAdapter(db)
        .mutate(f.operation(), TagMutation.create(second, '旅行'));
    posting = f.expense();
    selections = [TagSelection(first, 1), TagSelection(second, 1)];
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
    File('${work.path}/stage'),
    openDatabase: (file) => ProbeDatabase(
      file,
      storageBinding: allocationBinding(),
      tagsAware: true,
    ),
  );
  test('combined classifications and tags round-trip after rename merge archive and replay', () async {
    await FinancialWorkflows(db).post(posting, tags: selections);
    await TagsAdapter(db)
        .mutate(f.operation(), TagMutation.rename(first, 1, '差旅'));
    await TagsAdapter(db)
        .mutate(f.operation(), TagMutation.merge(first, 2, second, 1));
    await TagsAdapter(db)
        .mutate(f.operation(), TagMutation.archive(second, 1, true));
    final before = await codec.capture(db);
    expect(
      (await FinancialWorkflows(
        db,
      ).post(posting, tags: selections.reversed)).replayed,
      isTrue,
    );
    expect(await codec.capture(db), before);
    await stage(before);
    expect(
      await FinancialWorkflows(db).ledger.balance(f.reference),
      f.money('90'),
    );
    await expectLater(
      FinancialWorkflows(db).post(posting, tags: selections.take(1)),
      throwsA(isA<OperationConflict>()),
    );
    expect(
      () => SnapshotCodec(categoryReferences: true).canonicalize(before),
      throwsA(isA<InvalidSnapshot>()),
    );
  });
  test('stale missing duplicate and cross-workspace tags reject the entire financial write', () async {
    final before = await codec.capture(db);
    for (final tags in [
      [TagSelection(first, 2)],
      [TagSelection(PublicId.generate(), 1)],
      [TagSelection(first, 1), TagSelection(first, 1)],
    ]) {
      await expectLater(
        Future.sync(() => FinancialWorkflows(db).post(posting, tags: tags)),
        tags.length == 2 ? throwsArgumentError : throwsException,
      );
      expect(await codec.capture(db), before);
    }
    final foreign = OperationKey(
      WorkspaceId(PublicId.generate()),
      OperationId(PublicId.generate()),
    );
    final tag = PublicId.generate();
    await TagsAdapter(db).mutate(foreign, TagMutation.create(tag, '別的帳本'));
    final current = await codec.capture(db);
    await expectLater(
      FinancialWorkflows(db).post(posting, tags: [TagSelection(tag, 1)]),
      throwsException,
    );
    expect(await codec.capture(db), current);
  });
  for (final point in ['tag', 'tag-history', 'receipt', 'audit']) {
    test('metadata failure at $point is atomic and can retry', () async {
      final before = await codec.capture(db),
          operation = f.operation(),
          mutation = TagMutation.rename(first, 1, 'changed');
      await expectLater(
        TagsAdapter(db).mutate(
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
        (await TagsAdapter(db).mutate(operation, mutation)).replayed,
        isFalse,
      );
      await codec.capture(db);
    });
  }
  for (final point in ['tags', 'receipt', 'audit']) {
    test(
      'tagged posting failure at $point rolls back amounts references and audit',
      () async {
        final before = await codec.capture(db);
        await expectLater(
          FinancialWorkflows(db).post(
            posting,
            tags: selections,
            checkpoint: (p) {
              if (p == point) throw StateError('injected');
            },
          ),
          throwsStateError,
        );
        expect(await codec.capture(db), before);
        await FinancialWorkflows(db).post(posting, tags: selections);
        await codec.capture(db);
      },
    );
  }
  for (final change in [
    'missing-tag',
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
        await FinancialWorkflows(db).post(posting, tags: selections);
        await TagsAdapter(db)
            .mutate(f.operation(), TagMutation.archive(first, 1, true));
        final before = await codec.capture(db);
        final root = jsonDecode(utf8.decode(before)) as Map;
        final tables = root['tables'] as Map;
        final rows = tables['event_tags'] as List;
        final row = rows.first as Map;
        final receipts = tables['receipts'] as List;
        final receipt = receipts.cast<Map>().firstWhere(
          (r) => r['result_id'] == posting.id.value,
        );
        final input = jsonDecode(receipt['input'] as String) as List;
        switch (change) {
          case 'missing-tag':
            row['tag_id'] = PublicId.generate().value;
          case 'version':
            row['tag_version'] = '999';
          case 'before-selection':
            row['tag_sequence'] = '1';
          case 'after-archive':
            for (final r in rows) {
              r['tag_sequence'] = '3';
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
            input[2][1] = input[2][0];
            receipt['input'] = jsonEncode(input);
          case 'history':
            (tables['tag_changes'] as List).removeAt(0);
          case 'unknown-module':
            root['modules']['tags'] = 2;
        }
        await expectLater(
          stage(utf8.encode(jsonEncode(root))),
          throwsA(anyOf(isA<InvalidSnapshot>(), isA<SqliteException>())),
        );
        expect(await codec.capture(db), before);
      },
    );
  }
  test(
    'backup refuses duplicate tag references if source constraints were lost',
    () async {
      await FinancialWorkflows(db).post(posting, tags: selections);
      await db.customStatement(
        'CREATE TABLE broken_tags AS SELECT * FROM event_tags',
      );
      await db.customStatement('DROP TABLE event_tags');
      await db.customStatement('ALTER TABLE broken_tags RENAME TO event_tags');
      await db.customStatement(
        'INSERT INTO event_tags SELECT * FROM event_tags',
      );
      await expectLater(codec.capture(db), throwsA(isA<InvalidSnapshot>()));
    },
  );
}
