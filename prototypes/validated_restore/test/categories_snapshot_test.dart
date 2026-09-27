import 'dart:convert';
import 'dart:io';

import 'package:categories/categories.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:modular_persistence_probe/categories_adapter.dart';
import 'package:modular_persistence_probe/database.dart';
import 'package:modular_persistence_probe/storage_binding.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:validated_restore_probe/snapshot.dart';

void main() {
  final root = Directory('.dart_tool/category-snapshot-tests')
    ..createSync(recursive: true);
  final codec = SnapshotCodec(categoryAware: true);
  StorageBinding binding() => StorageBinding(
    PublicId.generate(),
    PublicId.generate(),
    OperationId(PublicId.generate()),
    'b' * 64,
  );
  late Directory work;
  late List<int> legacy;
  late WorkspaceId ws;
  setUp(() async {
    work = root.createTempSync('case-');
    final raw = sqlite3.open('${work.path}/old');
    raw.execute(
      File('../modular_persistence/test/fixtures/v1.sql').readAsStringSync(),
    );
    raw.close();
    final old = ProbeDatabase(
      File('${work.path}/old'),
      storageBinding: binding(),
    );
    try {
      legacy = await SnapshotCodec(generationAware: true).capture(old);
    } finally {
      await old.close();
    }
    final parsed = jsonDecode(utf8.decode(legacy)) as Map;
    ws = WorkspaceId.parse(
      parsed['tables']['accounts'][0]['workspace'] as String,
    );
  });
  tearDown(() {
    if (!work.resolveSymbolicLinksSync().startsWith(
      '${root.resolveSymbolicLinksSync()}${Platform.pathSeparator}',
    ))
      throw StateError('Unsafe cleanup');
    work.deleteSync(recursive: true);
  });
  Future<ProbeDatabase> stage(
    List<int> bytes,
    String name, {
    void Function(String)? checkpoint,
  }) async {
    final identity = binding();
    final file = File('${work.path}/$name');
    await codec.stage(
      bytes,
      file,
      checkpoint: checkpoint,
      openDatabase: (f) =>
          ProbeDatabase(f, storageBinding: identity, categoryAware: true),
    );
    return ProbeDatabase(file, storageBinding: identity, categoryAware: true);
  }

  OperationKey op() => OperationKey(ws, OperationId(PublicId.generate()));

  test(
    'known old snapshot upgrades in a new stage with empty category module',
    () async {
      final db = await stage(legacy, 'new');
      try {
        final after = await codec.capture(db);
        expect(after, codec.canonicalize(legacy));
        final parsed = jsonDecode(utf8.decode(after)) as Map;
        expect(parsed['version'], 3);
        expect(parsed['schema'], 4);
        expect(parsed['modules']['categories'], 1);
        expect(parsed['tables']['categories'], isEmpty);
        expect(parsed['tables']['category_changes'], isEmpty);
        expect(
          () => SnapshotCodec(generationAware: true).canonicalize(after),
          throwsA(isA<InvalidSnapshot>()),
        );
      } finally {
        await db.close();
      }
    },
  );

  test(
    'all category authority, history and global receipts round trip exactly',
    () async {
      var db = await stage(legacy, 'source');
      final id = PublicId.generate(), target = PublicId.generate();
      final operation = op();
      final create = CategoryMutation.create(id, '飲食', CategoryKind.expense);
      final adapter = CategoriesAdapter(db);
      await adapter.mutate(operation, create);
      await adapter.mutate(
        op(),
        CategoryMutation.create(target, '餐飲', CategoryKind.expense),
      );
      await adapter.mutate(op(), CategoryMutation.rename(id, 1, '舊分類'));
      await adapter.mutate(op(), CategoryMutation.merge(id, 2, target, 1));
      final bytes = await codec.capture(db);
      await db.close();
      db = await stage(bytes, 'restored');
      try {
        expect(await codec.capture(db), bytes);
        final restored = CategoriesAdapter(db);
        expect((await restored.read(ws)).resolve(id).id, target);
        expect((await restored.mutate(operation, create)).replayed, isTrue);
        expect(await codec.capture(db), bytes);
      } finally {
        await db.close();
      }
    },
  );

  test(
    'metadata IDs do not inflate financial event receipt cardinality',
    () async {
      final db = await stage(legacy, 'collision');
      try {
        final parsed = jsonDecode(utf8.decode(legacy)) as Map;
        final event = PublicId.parse(
          parsed['tables']['events'][0]['id'] as String,
        );
        await CategoriesAdapter(db).mutate(
          op(),
          CategoryMutation.create(event, '分類', CategoryKind.expense),
        );
        await codec.capture(db);
      } finally {
        await db.close();
      }
    },
  );

  test('unknown category module or malformed column is rejected before stage creation', () async {
    final db = await stage(legacy, 'source');
    final id = PublicId.generate();
    await CategoriesAdapter(db)
        .mutate(op(), CategoryMutation.create(id, '分類', CategoryKind.expense));
    final bytes = await codec.capture(db);
    await db.close();
    for (final alteration in ['module', 'column', 'orphan']) {
      final parsed = jsonDecode(utf8.decode(bytes)) as Map;
      if (alteration == 'module') parsed['modules']['categories'] = 2;
      if (alteration == 'column')
        parsed['tables']['categories'][0]['unknown'] = 'x';
      if (alteration == 'orphan') parsed['tables']['category_changes'] = [];
      await expectLater(
        stage(utf8.encode(jsonEncode(parsed)), alteration),
        throwsA(isA<InvalidSnapshot>()),
      );
      if (alteration != 'orphan')
        expect(File('${work.path}/$alteration').existsSync(), isFalse);
    }
  });

  test(
    'legal-looking forged category state or command cannot pass history replay',
    () async {
      final db = await stage(legacy, 'source');
      await CategoriesAdapter(db).mutate(
        op(),
        CategoryMutation.create(
          PublicId.generate(),
          '分類',
          CategoryKind.expense,
        ),
      );
      final bytes = await codec.capture(db);
      await db.close();
      for (final alteration in ['state', 'command', 'sequence', 'audit']) {
        final parsed = jsonDecode(utf8.decode(bytes)) as Map;
        final tables = parsed['tables'] as Map;
        if (alteration == 'state') {
          final payload =
              jsonDecode(tables['categories'][0]['payload'] as String) as Map;
          payload['name'] = '偽造';
          tables['categories'][0]['payload'] = jsonEncode(payload);
        }
        if (alteration == 'command') {
          final receipt = (tables['receipts'] as List).firstWhere(
            (r) => (r['input'] as String).contains('category-v1'),
          );
          final input = jsonDecode(receipt['input'] as String) as List;
          input[3] = '偽造';
          receipt['input'] = jsonEncode(input);
        }
        if (alteration == 'sequence')
          tables['category_changes'][0]['ordinal'] = '2';
        if (alteration == 'audit') {
          final audit = (tables['audit'] as List).firstWhere(
            (r) => r['kind'] == 'category.create',
          );
          audit['kind'] = 'category.rename';
        }
        await expectLater(
          stage(utf8.encode(jsonEncode(parsed)), alteration),
          throwsA(isA<InvalidSnapshot>()),
        );
      }
    },
  );

  test(
    'stage failures keep source schema and all authority bytes unchanged',
    () async {
      final original = File('${work.path}/old').readAsBytesSync();
      for (final point in ['table:categories', 'table:category_changes']) {
        await expectLater(
          stage(
            legacy,
            point.replaceAll(':', '-'),
            checkpoint: (at) {
              if (at == point) throw StateError('injected');
            },
          ),
          throwsStateError,
        );
        expect(File('${work.path}/old').readAsBytesSync(), original);
        final raw = sqlite3.open('${work.path}/old');
        expect(raw.userVersion, 3);
        raw.close();
      }
    },
  );
}
