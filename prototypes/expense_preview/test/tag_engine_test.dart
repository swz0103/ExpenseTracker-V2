import 'dart:convert';
import 'dart:io';

import 'package:backup_envelope_probe/envelope.dart';
import 'package:expense_preview/preview_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:tags/tags.dart';

import 'support.dart';

OperationKey op(PreviewEngine e) =>
    OperationKey(e.workspace, OperationId(PublicId.generate()));
Future<List<int>> snapshot(PreviewEngine e) async =>
    EnvelopeCodec().openWithPassword(await e.exportBackup(), password);
void main() {
  final root = Directory('.dart_tool/tag-app-tests')
    ..createSync(recursive: true);
  late Directory work;
  late MemoryVault vault;
  late PreviewEngine engine;
  setUp(() {
    work = root.createTempSync('case-');
    vault = MemoryVault();
    engine = engineAt(
      Directory('${work.path}/source'),
      vault,
      schemaVersion: 6,
    );
  });
  void remove(Directory d) {
    if (!d.resolveSymbolicLinksSync().startsWith(
      '${root.resolveSymbolicLinksSync()}${Platform.pathSeparator}',
    )) {
      throw StateError('Unsafe cleanup');
    }
    d.deleteSync(recursive: true);
  }

  tearDown(() async {
    await engine.lock();
    remove(work);
  });
  for (final version in [3, 4, 5]) {
    test(
      'App upgrade from schema $version requires confirmation then enables tags without changing amounts',
      () async {
        engine = engineAt(engine.directory, vault, schemaVersion: version);
        await setup(engine);
        final a = account(engine);
        await engine.createAccount(a, opening(a));
        await engine.post(income(a));
        final before = jsonDecode(utf8.decode(await snapshot(engine))) as Map;
        await engine.lock();
        engine = engineAt(engine.directory, vault, schemaVersion: 6);
        await expectLater(
          engine.unlock(password),
          throwsA(isA<PreviewUpgradeRequired>()),
        );
        await engine.upgrade(password);
        final after = jsonDecode(utf8.decode(await snapshot(engine))) as Map;
        expect(after['schema'], 6);
        expect(after['tables']['events'], before['tables']['events']);
        expect(after['tables']['legs'], before['tables']['legs']);
        await engine.createTag(op(engine), PublicId.generate(), '情境');
        expect((await engine.tags()).tags.single.name, '情境');
        expect(
          (await engine.accounts()).single.balance.minorUnits,
          BigInt.from(10700),
        );
      },
    );
  }
  for (final recovery in [false, true]) {
    test(
      'clean ${recovery ? 'recovery' : 'password'} restore retains original tag versions replay merge and amounts',
      () async {
        final key = await setup(engine);
        final a = account(engine);
        await engine.createAccount(a, opening(a));
        final x = PublicId.generate(), y = PublicId.generate();
        await engine.createTag(op(engine), x, '出差');
        await engine.createTag(op(engine), y, '旅行');
        final p = income(a);
        final selected = [TagSelection(x, 1), TagSelection(y, 1)];
        await engine.post(p, tags: selected);
        var catalog = await engine.tags();
        await engine.renameTag(op(engine), catalog.get(x), '差旅');
        catalog = await engine.tags();
        await engine.mergeTag(op(engine), catalog.get(x), catalog.get(y));
        catalog = await engine.tags();
        await engine.archiveTag(op(engine), catalog.get(y), archived: true);
        await engine.post(p, tags: selected.reversed);
        final full = await snapshot(engine),
            backup = await engine.exportBackup();
        final source = engine.directory;
        await engine.lock();
        remove(source);
        vault.values.clear();
        engine = engineAt(
          Directory('${work.path}/clean'),
          MemoryVault(),
          schemaVersion: 6,
        );
        await setup(engine);
        await engine.importBackup(
          backup,
          recovery ? key : password,
          recovery: recovery,
        );
        expect(await snapshot(engine), full);
        expect((await engine.tags()).resolve(x).id, y);
        expect(
          (await engine.tagsFor(p.id)).map((r) => r.version),
          everyElement(1),
        );
        await engine.post(p, tags: selected);
        expect(await snapshot(engine), full);
        expect(
          (await engine.accounts()).single.balance.minorUnits,
          BigInt.from(10700),
        );
        await engine.lock();
        await engine.unlock(password);
        expect((await engine.tagsFor(p.id)).length, 2);
      },
    );
  }
  test(
    '16 tags work atomically; 17 and stale references leave no financial write',
    () async {
      await setup(engine);
      final a = account(engine);
      await engine.createAccount(a, opening(a));
      final ids = List.generate(17, (_) => PublicId.generate());
      for (final id in ids) {
        await engine.createTag(op(engine), id, '情境');
      }
      final before = await snapshot(engine);
      await expectLater(
        engine.post(
          income(a),
          tags: [for (final id in ids) TagSelection(id, 1)],
        ),
        throwsArgumentError,
      );
      expect(await snapshot(engine), before);
      await expectLater(
        engine.post(income(a), tags: [TagSelection(ids.first, 2)]),
        throwsA(isA<TagException>()),
      );
      expect(await snapshot(engine), before);
      final p = income(a);
      await engine.post(
        p,
        tags: [for (final id in ids.take(16)) TagSelection(id, 1)],
      );
      expect((await engine.tagsFor(p.id)).length, 16);
      expect(
        (await engine.accounts()).single.balance.minorUnits,
        BigInt.from(10700),
      );
    },
  );
  test('tag-only workspace is retained on backup import and foreign commands are refused', () async {
    await setup(engine);
    final workspace = engine.workspace, id = PublicId.generate();
    await engine.createTag(op(engine), id, '只有標籤');
    final backup = await engine.exportBackup();
    final full = await snapshot(engine);
    await expectLater(
      engine.createTag(
        OperationKey(
          WorkspaceId(PublicId.generate()),
          OperationId(PublicId.generate()),
        ),
        PublicId.generate(),
        'foreign',
      ),
      throwsA(isA<PreviewInvalid>()),
    );
    expect(await snapshot(engine), full);
    await engine.lock();
    engine = engineAt(
      Directory('${work.path}/target'),
      MemoryVault(),
      schemaVersion: 6,
    );
    await setup(engine);
    await engine.importBackup(backup, password, recovery: false);
    expect(engine.workspace, workspace);
    expect((await engine.tags()).get(id).name, '只有標籤');
  });
  for (final point in [
    'backup:created',
    'table:event_tags',
    'publishing',
    'published',
  ]) {
    test(
      'App interrupted 5-to-6 at $point resumes with retained credentials',
      () async {
        engine = engineAt(engine.directory, vault, schemaVersion: 5);
        await setup(engine);
        final a = account(engine);
        await engine.createAccount(a, opening(a));
        await engine.lock();
        engine = engineAt(
          engine.directory,
          vault,
          schemaVersion: 6,
          checkpoint: (p) {
            if (p == '5:$point') throw StateError('injected');
          },
        );
        await expectLater(engine.upgrade(password), throwsException);
        await engine.lock();
        engine = engineAt(engine.directory, vault, schemaVersion: 6);
        try {
          await engine.unlock(password);
        } on PreviewUpgradeRequired {
          await engine.upgrade(password);
        }
        expect(
          (await engine.accounts()).single.balance.minorUnits,
          BigInt.from(10000),
        );
        await engine.createTag(op(engine), PublicId.generate(), '恢復後');
        await snapshot(engine);
      },
    );
  }
}
