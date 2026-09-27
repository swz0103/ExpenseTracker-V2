import 'dart:convert';
import 'dart:io';

import 'package:backup_envelope_probe/envelope.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:ledger_generation_probe/ledger_store.dart';
import 'package:storage_generation_probe/generation_store.dart';
import 'package:test/test.dart';

import 'support/merchant_upgrade_fixture.dart';

void main() {
  final root = Directory('.dart_tool/merchant-upgrade-tests')
    ..createSync(recursive: true);
  late MerchantUpgradeFixture f;
  setUp(() async {
    f = MerchantUpgradeFixture(root.createTempSync('case-'));
    await f.initialize();
  });
  tearDown(() => removeMerchantUpgradeFixture(root, f.directory));
  Future<void> intact() async {
    final original = await LedgerPayload(tagsAware: true).inspect(
      f.store().generations.databaseFile(f.original.generation),
      await f.keys.read(f.original.slot),
      f.original,
    );
    expect(utf8.encode(original), f.before);
  }

  test('explicit schema 6 to 7 preserves allocations source DB and original credentials', () async {
    await expectLater(
      f.store().withSession((s) => s.post(f.income())),
      throwsStateError,
    );
    final receipt = await f.upgrade();
    expect(receipt.target.generation, isNot(f.original.generation));
    expect(await f.store().snapshot(), f.expected);
    await intact();
    final saved = await f.backupFile.readAsString();
    expect(
      await EnvelopeCodec().openWithPassword(saved, merchantPassword),
      f.before,
    );
    expect(
      await EnvelopeCodec().openWithRecovery(saved, f.credential.recoveryKey),
      f.before,
    );
    await f.store().withSession((s) async {
      expect(
        (await s.post(f.priorIncome, tags: [TagSelection(f.tag, 1)])).replayed,
        isTrue,
      );
      final id = PublicId.generate();
      await s.createMerchant(f.operation(), id, '旅行');
      final p = f.expense();
      await s.post(p, merchant: MerchantSelection(id, 1));
      expect((await s.merchantFor(f.workspace, p.id))!.id, id);
    });
    final later = await f.store().snapshot();
    await f.upgrade();
    expect(await f.store().snapshot(), later);
  });
  test('source changes invalidate merchant upgrade plan without publishing or creating backup', () async {
    await f.store(merchants: false).withSession((s) => s.post(f.income()));
    final current = await f.store().snapshot();
    await expectLater(f.upgrade(), throwsA(isA<GenerationUnavailable>()));
    expect(await f.store().snapshot(), current);
    expect(f.backups.listSync(), isEmpty);
  });
  for (final point in [
    'backup:created',
    'backup:written',
    'backup:verified',
    'upgradeRecording',
    'reserved',
    'table:merchant_changes',
    'table:event_merchants',
    'staged',
    'validated',
    'publishing',
    'published',
  ]) {
    test(
      'native process exits at $point preserve source or complete target and allow safe retry',
      () async {
        final result = await f.childUpgrade(point);
        expect(result.exitCode, 73, reason: result.stderr.toString());
        expect(
          await f.store().snapshot(),
          point == 'published' ? f.expected : f.before,
        );
        await intact();
        final bytes = f.backupFile.readAsBytesSync();
        if (point == 'backup:created') {
          expect(bytes, isEmpty);
          await expectLater(f.upgrade(), throwsA(isA<GenerationUnavailable>()));
          await f.plan();
        } else {
          final backup = await f.backupFile.readAsString();
          expect(
            await EnvelopeCodec().openWithPassword(backup, merchantPassword),
            f.before,
          );
          expect(
            await EnvelopeCodec().openWithRecovery(
              backup,
              f.credential.recoveryKey,
            ),
            f.before,
          );
        }
        final retried = await f.childUpgrade('none');
        expect(retried.exitCode, 0, reason: retried.stderr.toString());
        expect(await f.store().snapshot(), f.expected);
        await intact();
        if (point != 'backup:created')
          expect(f.backupFile.readAsBytesSync(), bytes);
      },
    );
  }
}
