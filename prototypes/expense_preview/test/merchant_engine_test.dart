import 'dart:convert';
import 'dart:io';

import 'package:backup_envelope_probe/envelope.dart';
import 'package:expense_preview/preview_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:merchants/merchants.dart';

import 'support.dart';

OperationKey op(PreviewEngine e) =>
    OperationKey(e.workspace, OperationId(PublicId.generate()));
Future<List<int>> snapshot(PreviewEngine e) async =>
    EnvelopeCodec().openWithPassword(await e.exportBackup(), password);
void main() {
  final root = Directory('.dart_tool/merchant-app-tests')
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
      schemaVersion: 7,
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
  for (final version in [3, 4, 5, 6]) {
    test(
      'App upgrade from schema $version requires confirmation then enables merchants without changing amounts',
      () async {
        engine = engineAt(engine.directory, vault, schemaVersion: version);
        await setup(engine);
        final a = account(engine);
        await engine.createAccount(a, opening(a));
        await engine.post(income(a));
        final before = jsonDecode(utf8.decode(await snapshot(engine))) as Map;
        await engine.lock();
        engine = engineAt(engine.directory, vault, schemaVersion: 7);
        await expectLater(
          engine.unlock(password),
          throwsA(isA<PreviewUpgradeRequired>()),
        );
        await engine.upgrade(password);
        final after = jsonDecode(utf8.decode(await snapshot(engine))) as Map;
        expect(after['schema'], 7);
        expect(after['tables']['events'], before['tables']['events']);
        expect(after['tables']['legs'], before['tables']['legs']);
        await engine.createMerchant(op(engine), PublicId.generate(), '情境');
        expect((await engine.merchants()).merchants.single.name, '情境');
        expect(
          (await engine.accounts()).single.balance.minorUnits,
          BigInt.from(10700),
        );
      },
    );
  }
  for (final recovery in [false, true]) {
    test(
      'clean ${recovery ? 'recovery' : 'password'} restore retains original merchant versions replay merge and amounts',
      () async {
        final key = await setup(engine);
        final a = account(engine);
        await engine.createAccount(a, opening(a));
        final x = PublicId.generate(), y = PublicId.generate();
        await engine.createMerchant(op(engine), x, '出差');
        await engine.createMerchant(op(engine), y, '旅行');
        final p = income(a);
        final selected = MerchantSelection(x, 1);
        final tagId = PublicId.generate();
        await engine.createTag(op(engine), tagId, '情境');
        final tags = [TagSelection(tagId, 1)];
        await engine.post(p, merchant: selected, tags: tags);
        var catalog = await engine.merchants();
        await engine.renameMerchant(op(engine), catalog.get(x), '差旅');
        catalog = await engine.merchants();
        await engine.changeMerchantAlias(
          op(engine),
          catalog.get(x),
          'CARD SHOP',
          remove: false,
        );
        catalog = await engine.merchants();
        await engine.mergeMerchant(op(engine), catalog.get(x), catalog.get(y));
        catalog = await engine.merchants();
        await engine.archiveMerchant(
          op(engine),
          catalog.get(y),
          archived: true,
        );
        await engine.post(p, merchant: selected, tags: tags);
        final full = await snapshot(engine),
            backup = await engine.exportBackup();
        final source = engine.directory;
        await engine.lock();
        remove(source);
        vault.values.clear();
        engine = engineAt(
          Directory('${work.path}/clean'),
          MemoryVault(),
          schemaVersion: 7,
        );
        await setup(engine);
        await engine.importBackup(
          backup,
          recovery ? key : password,
          recovery: recovery,
        );
        expect(await snapshot(engine), full);
        expect((await engine.merchants()).resolve(x).id, y);
        expect((await engine.merchantFor(p.id))!.version, 1);
        await engine.post(p, merchant: selected, tags: tags);
        expect(await snapshot(engine), full);
        expect(
          (await engine.accounts()).single.balance.minorUnits,
          BigInt.from(10700),
        );
        await engine.lock();
        await engine.unlock(password);
        expect((await engine.merchantFor(p.id))!.id, x);
        expect((await engine.merchants()).get(x).aliases, ['CARD SHOP']);
        expect((await engine.tagsFor(p.id)).single.id, tagId);
      },
    );
  }
  test('aliases preserve exact encoded capacity and stale merchant selection rolls back', () async {
    await setup(engine);
    final a = account(engine);
    await engine.createAccount(a, opening(a));
    final id = PublicId.generate();
    await engine.createMerchant(op(engine), id, '商家');
    for (var i = 0; i < 16; i++) {
      final merchant = (await engine.merchants()).get(id);
      await engine.changeMerchantAlias(
        op(engine),
        merchant,
        '別名$i',
        remove: false,
      );
    }
    final full = await snapshot(engine),
        current = (await engine.merchants()).get(id);
    await expectLater(
      engine.changeMerchantAlias(op(engine), current, '第十七個', remove: false),
      throwsA(isA<MerchantException>()),
    );
    expect(await snapshot(engine), full);
    await expectLater(
      engine.post(income(a), merchant: MerchantSelection(id, 1)),
      throwsA(isA<MerchantException>()),
    );
    expect(await snapshot(engine), full);
    final posting = income(a);
    await engine.post(
      posting,
      merchant: MerchantSelection(id, current.version),
    );
    expect((await engine.merchantFor(posting.id))!.version, 17);
    await engine.changeMerchantAlias(op(engine), current, '別名0', remove: true);
    await engine.post(posting, merchant: MerchantSelection(id, 17));
    expect(
      (await engine.accounts()).single.balance.minorUnits,
      BigInt.from(10700),
    );
    await snapshot(engine);
  });
  test('merchant-only workspace is retained on backup import and foreign commands are refused', () async {
    await setup(engine);
    final workspace = engine.workspace, id = PublicId.generate();
    await engine.createMerchant(op(engine), id, '只有標籤');
    final backup = await engine.exportBackup();
    final full = await snapshot(engine);
    await expectLater(
      engine.createMerchant(
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
      schemaVersion: 7,
    );
    await setup(engine);
    await engine.importBackup(backup, password, recovery: false);
    expect(engine.workspace, workspace);
    expect((await engine.merchants()).get(id).name, '只有標籤');
  });
  for (final point in [
    'backup:created',
    'table:event_merchants',
    'publishing',
    'published',
  ]) {
    test(
      'App interrupted 6-to-7 at $point resumes with retained credentials',
      () async {
        engine = engineAt(engine.directory, vault, schemaVersion: 6);
        await setup(engine);
        final a = account(engine);
        await engine.createAccount(a, opening(a));
        await engine.lock();
        engine = engineAt(
          engine.directory,
          vault,
          schemaVersion: 7,
          checkpoint: (p) {
            if (p == '6:$point') throw StateError('injected');
          },
        );
        await expectLater(engine.upgrade(password), throwsException);
        await engine.lock();
        engine = engineAt(engine.directory, vault, schemaVersion: 7);
        try {
          await engine.unlock(password);
        } on PreviewUpgradeRequired {
          await engine.upgrade(password);
        }
        expect(
          (await engine.accounts()).single.balance.minorUnits,
          BigInt.from(10000),
        );
        await engine.createMerchant(op(engine), PublicId.generate(), '恢復後');
        await snapshot(engine);
      },
    );
  }
}
