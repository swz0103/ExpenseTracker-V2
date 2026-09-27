import 'dart:io';

import 'package:amount_input/amount_input.dart';
import 'package:backup_envelope_probe/envelope.dart';
import 'package:categories/categories.dart';
import 'package:expense_preview/preview_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundation_values/foundation_values.dart';

import 'support.dart';

void main() {
  test('all allocation modes persist as ordinary drafts, replay once and survive password/recovery restoration without source keys', () async {
    final root = Directory('.dart_tool/split-assist-tests')
      ..createSync(recursive: true);
    final work = root.createTempSync('case-'),
        app = Directory('${work.path}/app');
    final vault = MemoryVault();
    var stop = false;
    final engine = engineAt(
      app,
      vault,
      schemaVersion: 9,
      draftCheckpoint: (p) {
        if (stop && p == 'draft-committed') throw StateError('injected');
      },
    );
    try {
      final recovery = await setup(engine);
      final a = account(engine);
      await engine.createAccount(a, opening(a));
      final categories = List.generate(3, (_) => PublicId.generate());
      for (var i = 0; i < 3; i++) {
        await engine.createCategory(
          OperationKey(engine.workspace, OperationId(PublicId.generate())),
          categories[i],
          '分類 $i',
          CategoryKind.expense,
        );
      }
      final expected = <PublicId, List<int>>{};
      for (final method in SplitMethod.values) {
        final p = proposeSplit(
          Money.parse(a.currency, '10'),
          rows: 3,
          method: method,
          weights: switch (method) {
            SplitMethod.equal => const [],
            SplitMethod.percentage => ['33.33', '33.33', '33.34'],
            SplitMethod.ratio => ['1', '2', '3'],
          },
        );
        final draft = await engine.saveEntryDraft(
          EntryFields(
            income: false,
            split: true,
            accountId: a.id,
            amount: '10',
            date: '2026-09-28',
            splits: [
              for (var i = 0; i < 3; i++)
                SplitFields(
                  categoryId: categories[i],
                  amount: p.amounts[i].majorText,
                ),
            ],
          ),
        );
        expected[draft.id] = method == SplitMethod.ratio
            ? [166, 333, 501]
            : [333, 333, 334];
        await engine.lock();
        await engine.unlock(password);
        expect((await engine.entryDraft())!.encode(), draft.encode());
        stop = true;
        await expectLater(engine.submitEntryDraft(), throwsStateError);
        stop = false;
        expect(
          await engine.entryDraft(),
          null,
        ); // Resolves the committed receipt exactly once.
        expect((await engine.entries()).length, expected.length + 1);
      }
      final backup = await engine.exportBackup();
      final snapshot = await EnvelopeCodec().openWithPassword(backup, password);
      await engine.lock();
      deleteSynthetic(app, work);
      vault.values.clear();
      for (final rescue in [false, true]) {
        final restored = engineAt(
          Directory('${work.path}/restore-$rescue'),
          MemoryVault(),
          schemaVersion: 9,
        );
        try {
          await setup(restored);
          await restored.importBackup(
            backup,
            rescue ? recovery : password,
            recovery: rescue,
          );
          await restored.lock();
          await restored.unlock(password);
          expect((await restored.entries()).length, 4);
          expect(
            (await restored.accounts()).single.balance.minorUnits,
            BigInt.from(7000),
          );
          for (final e in expected.entries) {
            final rows = await restored.allocations(e.key);
            for (var i = 0; i < 3; i++) {
              expect(
                rows
                    .singleWhere((r) => r.categoryId == categories[i])
                    .amount
                    .minorUnits,
                BigInt.from(e.value[i]),
              );
            }
          }
          expect(
            await EnvelopeCodec().openWithPassword(
              await restored.exportBackup(),
              password,
            ),
            snapshot,
          );
        } finally {
          await restored.lock();
        }
      }
    } finally {
      await engine.lock();
      deleteSynthetic(work, root);
    }
  });
}
