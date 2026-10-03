import 'dart:io';

import 'package:categories/categories.dart';
import 'package:expense_preview/main.dart';
import 'package:expense_preview/preview_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundation_values/foundation_values.dart';

import 'support.dart';
import 'widget_test.dart' show Documents, settle, tap, input, closeEngine;

void main() {
  for (final scenario in ['apply', 'lock-open', 'lock-queued']) {
    testWidgets(
      'split allocation $scenario preserves draft identity and lock boundary',
      (t) async {
        final root = Directory('.dart_tool/widget-tests')
          ..createSync(recursive: true);
        final work = root.createTempSync('split-assist-');
        final engine = engineAt(work, MemoryVault(), schemaVersion: 9);
        late EntryDraft original;
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        Future<void> visible(Finder f) async {
          if (f.evaluate().isEmpty) {
            await t.scrollUntilVisible(
              f,
              160,
              scrollable: find.byType(Scrollable).first,
            );
          }
          await t.ensureVisible(f);
          await t.pump(const Duration(milliseconds: 350));
        }

        try {
          await t.runAsync(() async {
            await setup(engine);
            final a = account(engine);
            await engine.createAccount(a, opening(a));
            final ids = List.generate(3, (_) => PublicId.generate());
            for (var i = 0; i < 3; i++) {
              await engine.createCategory(
                OperationKey(
                  engine.workspace,
                  OperationId(PublicId.generate()),
                ),
                ids[i],
                '私人分類 $i',
                CategoryKind.expense,
              );
            }
            original = await engine.saveEntryDraft(
              EntryFields(
                income: false,
                split: true,
                accountId: a.id,
                amount: '10',
                date: '2026-09-28',
                splits: [
                  for (var i = 0; i < 3; i++)
                    SplitFields(categoryId: ids[i], amount: ['2', '3', '5'][i]),
                ],
              ),
            );
            await engine.lock();
          });
          await t.pumpWidget(
            PreviewApp(engine: Future.value(engine), documents: Documents()),
          );
          await settle(t);
          await input(t, '密碼', password);
          await tap(t, '解鎖');
          await tap(t, '繼續草稿');
          await visible(find.widgetWithText(OutlinedButton, '分配拆分金額'));
          await t.tap(find.widgetWithText(OutlinedButton, '分配拆分金額'));
          // The underlying form is busy until the modal is closed.
          for (
            var i = 0;
            i < 120 && find.byType(AlertDialog).evaluate().isEmpty;
            i++
          ) {
            await t.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 25)),
            );
            await t.pump();
          }
          await t.pump(const Duration(milliseconds: 350));
          expect(find.byType(AlertDialog), findsOneWidget);
          await visible(find.text('預覽分配'));
          await t.tap(find.text('預覽分配'));
          await t.pump(const Duration(milliseconds: 350));
          if (scenario == 'apply') {
            await t.tap(find.text('套用分配'));
            await settle(t);
            // Lock flushes the asynchronous encrypted draft, then a new view resumes it.
            await t.tap(find.byTooltip('鎖定'));
            await settle(t);
          } else {
            if (scenario == 'lock-queued') {
              t
                  .widget<FilledButton>(
                    find.widgetWithText(FilledButton, '套用分配'),
                  )
                  .onPressed!();
            }
            t.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.inactive,
            );
            await settle(t);
            expect(find.textContaining('私人分類'), findsNothing);
            expect(find.byType(AlertDialog), findsNothing);
            t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
          }
          await input(t, '密碼', password);
          await tap(t, '解鎖');
          await t.runAsync(() async {
            final saved = (await engine.entryDraft())!;
            expect(saved.id, original.id);
            expect(
              saved.fields.splits.map((r) => r.categoryId),
              original.fields.splits.map((r) => r.categoryId),
            );
            expect(
              saved.fields.splits.map((r) => r.amount),
              scenario == 'apply' ? ['3.34', '3.33', '3.33'] : ['2', '3', '5'],
            );
            expect((await engine.entries()).length, 1);
            if (scenario == 'apply') {
              await engine.submitEntryDraft();
              expect(
                (await engine.allocations(original.id))
                    .map((r) => r.amount.minorUnits.toInt())
                    .toList()
                  ..sort(),
                [333, 333, 334],
              );
              expect(
                (await engine.accounts()).single.balance.minorUnits,
                BigInt.from(9000),
              );
            }
          });
          expect(t.takeException(), null);
        } finally {
          await t.pumpWidget(const SizedBox());
          await closeEngine(t, engine);
          deleteSynthetic(work, root);
        }
      },
    );
  }
}
