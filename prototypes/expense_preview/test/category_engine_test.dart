import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:backup_envelope_probe/envelope.dart';
import 'package:categories/categories.dart';
import 'package:expense_preview/preview_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';

import 'support.dart';

OperationKey operation(PreviewEngine engine) =>
    OperationKey(engine.workspace, OperationId(PublicId.generate()));

Future<List<int>> snapshot(PreviewEngine engine) async =>
    EnvelopeCodec().openWithPassword(await engine.exportBackup(), password);

void main() {
  final root = Directory('.dart_tool/category-app-tests')
    ..createSync(recursive: true);
  late Directory work;
  late MemoryVault vault;
  late PreviewEngine engine;
  setUp(() {
    work = root.createTempSync('case-');
    vault = MemoryVault();
    engine = engineAt(work, vault);
  });
  tearDown(() async {
    await engine.lock();
    if (!work.absolute.path.startsWith(
      '${root.absolute.path}${Platform.pathSeparator}',
    )) {
      throw StateError('unsafe cleanup');
    }
    work.deleteSync(recursive: true);
  });

  for (final schema in [3, 4]) {
    test(
      'schema $schema requires confirmation; upgrade preserves profile, source and both credentials',
      () async {
        engine = engineAt(work, vault, schemaVersion: schema);
        final key = await setup(engine);
        final a = account(engine);
        final first = opening(a);
        await engine.createAccount(a, first);
        final posting = income(a);
        await engine.post(posting);
        final before = await snapshot(engine);
        await engine.lock();
        final profile = File('${work.path}/profile.envelope').readAsBytesSync();
        final originalKeys = Map.of(vault.values);
        final originals = {
          for (final file
              in Directory('${work.path}/ledger')
                  .listSync(recursive: true)
                  .whereType<File>()
                  .where(
                    (f) =>
                        f.path.endsWith('.db') &&
                        !f.path.endsWith('catalog.db'),
                  ))
            file.path: file.readAsBytesSync(),
        };
        expect(originals, isNotEmpty);
        engine = engineAt(work, vault);
        await expectLater(
          engine.unlock(password),
          throwsA(isA<PreviewUpgradeRequired>()),
        );
        expect(engine.isUnlocked, isFalse);
        expect(Directory('${work.path}/upgrade-backups').existsSync(), isFalse);
        await expectLater(
          engine.upgrade('incorrect-password'),
          throwsA(isA<BackupException>()),
        );
        expect(vault.values, originalKeys);
        await engine.upgrade(password);
        expect(engine.workspace, a.workspace);
        await engine.post(posting);
        expect(
          (await engine.accounts()).single.balance.minorUnits,
          BigInt.from(10700),
        );
        final after = jsonDecode(utf8.decode(await snapshot(engine))) as Map;
        expect(after['schema'], 5);
        final backups =
            Directory('${work.path}/upgrade-backups')
                .listSync()
                .whereType<File>()
                .toList()
              ..sort((a, b) => a.path.compareTo(b.path));
        expect(backups, hasLength(5 - schema));
        expect(
          await EnvelopeCodec().openWithPassword(
            backups.first.readAsStringSync(),
            password,
          ),
          before,
        );
        expect(
          await EnvelopeCodec().openWithRecovery(
            backups.first.readAsStringSync(),
            key,
          ),
          before,
        );
        for (final entry in originals.entries) {
          expect(File(entry.key).readAsBytesSync(), entry.value);
        }
        for (final entry in originalKeys.entries) {
          expect(vault.values[entry.key], entry.value);
        }
        expect(
          File('${work.path}/profile.envelope').readAsBytesSync(),
          profile,
        );
        await engine.lock();
        engine = engineAt(work, vault);
        await engine.unlock(password);
        expect(
          (await engine.accounts()).single.balance.minorUnits,
          BigInt.from(10700),
        );
        expect(
          Directory('${work.path}/upgrade-backups').listSync(),
          hasLength(5 - schema),
        );
      },
    );
  }

  for (final point in [
    '3:backup:created',
    '3:publishing',
    '3:published',
    '4:backup:written',
    '4:validated',
    '4:published',
  ]) {
    test(
      'fresh App resumes after failure at $point without duplicating financial data',
      () async {
        engine = engineAt(work, vault, schemaVersion: 3);
        await setup(engine);
        final a = account(engine);
        await engine.createAccount(a, opening(a));
        final p = income(a);
        await engine.post(p);
        await engine.lock();
        var reached = false;
        engine = engineAt(
          work,
          vault,
          checkpoint: (current) {
            if (current == point) {
              reached = true;
              throw StateError('injected');
            }
          },
        );
        await expectLater(engine.upgrade(password), throwsA(anything));
        expect(reached, isTrue);
        expect(engine.isUnlocked, isFalse);
        await engine.lock();
        engine = engineAt(work, vault);
        await engine.upgrade(password);
        await engine.post(p);
        expect(
          (await engine.accounts()).single.balance.minorUnits,
          BigInt.from(10700),
        );
        expect(await engine.entries(), hasLength(2));
        expect(
          (jsonDecode(utf8.decode(await snapshot(engine))) as Map)['schema'],
          5,
        );
      },
    );
  }

  test('backgrounding during upgrade cannot reopen an unlocked App', () async {
    engine = engineAt(work, vault, schemaVersion: 3);
    await setup(engine);
    await engine.lock();
    engine = engineAt(
      work,
      vault,
      checkpoint: (point) {
        if (point == '3:backup:verified') unawaited(engine.lock());
      },
    );
    await expectLater(engine.upgrade(password), throwsA(anything));
    expect(engine.isUnlocked, isFalse);
    await expectLater(engine.categories(), throwsA(isA<PreviewLocked>()));
    engine = engineAt(work, vault);
    await engine.upgrade(password);
    expect(await engine.accounts(), isEmpty);
  });

  test('category-only workspace survives export, import and reopen; mixed workspace import is rejected', () async {
    await setup(engine);
    final id = PublicId.generate();
    final originalWorkspace = engine.workspace;
    await engine.createCategory(
      operation(engine),
      id,
      '餐飲',
      CategoryKind.expense,
    );
    final bytes = await snapshot(engine);
    final parsed = jsonDecode(utf8.decode(bytes)) as Map;
    final changed = jsonDecode(utf8.decode(bytes)) as Map;
    final other = Map<String, dynamic>.from(
      parsed['tables']['categories'][0] as Map,
    );
    other['workspace'] = WorkspaceId(PublicId.generate()).toString();
    other['id'] = PublicId.generate().value;
    (changed['tables']['categories'] as List).add(other);
    expect(
      () => validatePreviewSnapshot(utf8.encode(jsonEncode(changed))),
      throwsA(isA<PreviewInvalid>()),
    );
    final envelope = await engine.exportBackup();
    await engine.lock();
    engine = engineAt(Directory('${work.path}/target'), MemoryVault());
    await setup(engine);
    await engine.importBackup(envelope, password, recovery: false);
    expect(engine.workspace, originalWorkspace);
    expect((await engine.categories()).get(id).name, '餐飲');
    await engine.lock();
    await engine.unlock(password);
    expect(engine.workspace, originalWorkspace);
  });

  for (final recovery in [false, true]) {
    test(
      'classified history and replay survive archive and clean ${recovery ? 'recovery' : 'password'} restore without source keys',
      () async {
        final source = Directory('${work.path}/source');
        engine = engineAt(source, vault);
        final key = await setup(engine);
        final a = account(engine);
        await engine.createAccount(a, opening(a));
        final parentId = PublicId.generate(), childId = PublicId.generate();
        final create = operation(engine);
        await engine.createCategory(
          operation(engine),
          parentId,
          '飲食',
          CategoryKind.expense,
        );
        await engine.createCategory(
          create,
          childId,
          '午餐',
          CategoryKind.expense,
          parentId: parentId,
        );
        await engine.createCategory(
          create,
          childId,
          '午餐',
          CategoryKind.expense,
          parentId: parentId,
        );
        final p = Posting.expense(
          id: PublicId.generate(),
          operation: operation(engine),
          date: BusinessDate(2026, 9, 27),
          account: ref(a),
          amount: Money.parse(a.currency, '25.50'),
          allocations: [
            Allocation(
              childId,
              Money.parse(a.currency, '25.50'),
              expectedCategoryVersion: 1,
            ),
          ],
        );
        await engine.post(p);
        final allocation = (await engine.allocations(p.id)).single;
        expect(allocation.categoryId, childId);
        expect(allocation.categoryVersion, 1);
        final cat = (await engine.categories()).get(childId);
        await engine.renameCategory(operation(engine), cat, '午餐更新');
        await expectLater(
          engine.renameCategory(operation(engine), cat, 'stale'),
          throwsA(isA<CategoryException>()),
        );
        final current = (await engine.categories()).get(childId);
        await engine.archiveCategory(
          operation(engine),
          current,
          archived: true,
        );
        await engine.post(p);
        expect((await engine.allocations(p.id)).single.categoryVersion, 1);
        final before = await snapshot(engine);
        final envelope = await engine.exportBackup();
        await engine.lock();
        if (!source.resolveSymbolicLinksSync().startsWith(
          '${work.resolveSymbolicLinksSync()}${Platform.pathSeparator}',
        )) {
          throw StateError('unsafe cleanup');
        }
        source.deleteSync(recursive: true);
        vault.values.clear();
        engine = engineAt(Directory('${work.path}/clean'), MemoryVault());
        final newKey = await setup(engine);
        await engine.importBackup(
          envelope,
          recovery ? key : password,
          recovery: recovery,
        );
        await engine.post(p);
        expect(await snapshot(engine), before);
        expect(
          (await engine.accounts()).single.balance.minorUnits,
          BigInt.from(7450),
        );
        expect((await engine.categories()).get(childId).archived, isTrue);
        expect(
          await EnvelopeCodec().openWithRecovery(
            await engine.exportBackup(),
            newKey,
          ),
          before,
        );
        final invalid = Posting.expense(
          id: PublicId.generate(),
          operation: operation(engine),
          date: p.date,
          account: ref(a),
          amount: Money.parse(a.currency, '1'),
          allocations: [
            Allocation(
              childId,
              Money.parse(a.currency, '1'),
              expectedCategoryVersion: 3,
            ),
          ],
        );
        await expectLater(engine.post(invalid), throwsA(anything));
        expect(await snapshot(engine), before);
      },
    );
  }

  test('importing older V2 backup converts only the staged data and preserves local profile', () async {
    engine = engineAt(work, vault, schemaVersion: 3);
    await setup(engine);
    final a = account(engine);
    await engine.createAccount(a, opening(a));
    final old = await engine.exportBackup();
    await engine.lock();
    engine = engineAt(Directory('${work.path}/target'), MemoryVault());
    await setup(engine);
    await engine.importBackup(old, password, recovery: false);
    expect(
      (jsonDecode(utf8.decode(await snapshot(engine))) as Map)['schema'],
      5,
    );
    expect(
      (await engine.accounts()).single.balance.minorUnits,
      BigInt.from(10000),
    );
    final before = await snapshot(engine);
    final invalid = jsonDecode(utf8.decode(before)) as Map;
    invalid['schema'] = 99;
    final unsupported = await EnvelopeCodec().create(
      utf8.encode(jsonEncode(invalid)),
      password: password,
    );
    await expectLater(
      engine.importBackup(unsupported.envelope, password, recovery: false),
      throwsA(anything),
    );
    expect(await snapshot(engine), before);
  });
}
