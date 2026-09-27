import 'dart:io';

import 'package:amount_input/amount_input.dart';
import 'package:expense_preview/preview_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundation_values/foundation_values.dart';

import 'support.dart';

void main() {
  test('raw expression survives restart but cannot post; applied result retries once and clean restore is exact', () async {
    final root = Directory('.dart_tool/calculator-engine')
      ..createSync(recursive: true);
    final work = root.createTempSync('case-');
    final vault = MemoryVault();
    var interrupt = false;
    var engine = engineAt(
      work,
      vault,
      schemaVersion: 7,
      draftCheckpoint: (point) {
        if (interrupt && point == 'draft-committed') {
          interrupt = false;
          throw StateError('injected');
        }
      },
    );
    PreviewEngine? restored;
    try {
      await setup(engine);
      final a = account(engine);
      await engine.createAccount(a, opening(a));
      EntryFields fields(String amount) => EntryFields(
        income: false,
        accountId: a.id,
        amount: amount,
        date: '2026-09-27',
      );
      final first = await engine.saveEntryDraft(fields('0.1+0.2+1/3'));
      await engine.lock();
      engine = engineAt(
        work,
        vault,
        schemaVersion: 7,
        draftCheckpoint: (point) {
          if (interrupt && point == 'draft-committed') {
            interrupt = false;
            throw StateError('injected');
          }
        },
      );
      await engine.unlock(password);
      expect((await engine.entryDraft())!.fields.amount, '0.1+0.2+1/3');
      await expectLater(
        engine.submitEntryDraft(),
        throwsA(isA<MoneyException>()),
      );
      expect(await engine.entries(), hasLength(1));
      final result = calculateAmount(a.currency, '0.1+0.2+1/3');
      expect(result.money.majorText, '0.63');
      expect(result.rounded, isTrue);
      final applied = await engine.saveEntryDraft(
        fields(result.money.majorText),
      );
      expect(applied.id, first.id);
      expect(applied.operation, first.operation);
      interrupt = true;
      await expectLater(engine.submitEntryDraft(), throwsStateError);
      expect(await engine.entryDraft(), isNull);
      expect(await engine.entries(), hasLength(2));
      expect(
        (await engine.accounts()).single.balance.minorUnits,
        BigInt.from(9937),
      );
      final backup = await engine.exportBackup();
      await engine.lock();
      vault.values.clear();
      deleteSynthetic(Directory(work.path), root);
      final destination = root.createTempSync('clean-');
      restored = engineAt(destination, MemoryVault(), schemaVersion: 7);
      try {
        await setup(restored);
        await restored.importBackup(backup, password, recovery: false);
        expect(
          (await restored.accounts()).single.balance.minorUnits,
          BigInt.from(9937),
        );
        expect((await restored.entries()).map((e) => e.id), contains(first.id));
        await restored.lock();
        await restored.unlock(password);
        expect(await restored.entries(), hasLength(2));
      } finally {
        await restored.lock();
        deleteSynthetic(destination, root);
      }
    } finally {
      await engine.lock();
      if (work.existsSync()) deleteSynthetic(work, root);
    }
  });
}
