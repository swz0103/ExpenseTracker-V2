import 'dart:io';

import 'package:expense_preview/preview_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storage_generation_probe/generation_store.dart';

import 'support.dart';

void main() {
  final root = Directory('.dart_tool/correction-upgrade-tests')
    ..createSync(recursive: true);
  late Directory work;
  late MemoryVault vault;
  late PreviewEngine engine;

  setUp(() {
    work = root.createTempSync('case-');
    vault = MemoryVault();
    engine = engineAt(work, vault, schemaVersion: 12);
  });
  tearDown(() async {
    await engine.lock();
    deleteSynthetic(work, root);
  });

  test(
    'App 12 to 13 upgrade retains old generation on failure then resumes',
    () async {
      await setup(engine);
      final a = account(engine);
      await engine.createAccount(a, opening(a));
      await engine.post(income(a));
      final oldBalance = (await engine.accounts()).single.balance;
      final oldEntries = await engine.entries();
      await engine.lock();

      engine = engineAt(
        work,
        vault,
        schemaVersion: 13,
        checkpoint: (point) {
          if (point == '12:table:event_corrections') {
            throw StateError('injected');
          }
        },
      );
      await expectLater(
        engine.unlock(password),
        throwsA(isA<PreviewUpgradeRequired>()),
      );
      await expectLater(
        engine.upgrade(password),
        throwsA(isA<GenerationUnavailable>()),
      );
      await engine.lock();

      // The failed stage must leave the prior V2 data readable and exportable.
      engine = engineAt(work, vault, schemaVersion: 12);
      await engine.unlock(password);
      expect((await engine.accounts()).single.balance, oldBalance);
      expect(
        (await engine.entries()).map((e) => e.id),
        oldEntries.map((e) => e.id),
      );
      expect(await engine.exportBackup(), isNotEmpty);
      await engine.lock();

      engine = engineAt(work, vault, schemaVersion: 13);
      await engine.upgrade(password);
      expect(engine.capabilities.corrections, true);
      expect((await engine.accounts()).single.balance, oldBalance);
      expect(
        (await engine.entries()).map((e) => e.id),
        oldEntries.map((e) => e.id),
      );
      final envelope = await engine.exportBackup();
      expect(envelope, isNotEmpty);
      await engine.lock();
      await engine.unlock(password);
      expect((await engine.accounts()).single.balance, oldBalance);
    },
  );
}
