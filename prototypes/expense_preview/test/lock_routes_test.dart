import 'dart:io';

import 'package:expense_preview/main.dart';
import 'package:expense_preview/preview_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundation_values/foundation_values.dart';

import 'support.dart';
import 'widget_test.dart' show Documents, settle, tap, input, closeEngine;

void main() {
  for (final scenario in [
    'dialog',
    'queued-confirmation',
    'account',
    'tag-menu',
    'date-picker',
    'queued-date',
  ]) {
    testWidgets('background lock cancels $scenario and retains the draft', (
      tester,
    ) async {
      final root = Directory('.dart_tool/widget-tests')
        ..createSync(recursive: true);
      final work = root.createTempSync('lock-route-');
      final engine = engineAt(work, MemoryVault(), schemaVersion: 7);
      final tag = PublicId.generate();
      EntryDraft? saved;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      try {
        await tester.runAsync(() async {
          await setup(engine);
          final a = account(engine, name: '保密現金');
          await engine.createAccount(a, opening(a));
          await engine.createTag(
            OperationKey(engine.workspace, OperationId(PublicId.generate())),
            tag,
            '保密標籤',
          );
          saved = await engine.saveEntryDraft(
            EntryFields(
              income: false,
              amount: '12.50',
              date: '2026-09-27',
              accountId: a.id,
            ),
          );
          await engine.lock();
        });
        await tester.pumpWidget(
          PreviewApp(engine: Future.value(engine), documents: Documents()),
        );
        await settle(tester);
        await input(tester, '密碼', password);
        await tap(tester, '解鎖');
        if (scenario == 'dialog' || scenario == 'queued-confirmation') {
          await tester.ensureVisible(find.text('捨棄草稿'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('捨棄草稿'));
          for (
            var i = 0;
            i < 120 && find.byType(AlertDialog).evaluate().isEmpty;
            i++
          ) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 25)),
            );
            await tester.pump(const Duration(milliseconds: 25));
          }
          expect(find.byType(AlertDialog), findsOneWidget);
          if (scenario == 'queued-confirmation') {
            // Deliver the actual button callback, then lock before its awaiting
            // continuation can use the previous session.
            tester
                .widget<FilledButton>(find.widgetWithText(FilledButton, '確認捨棄'))
                .onPressed!();
          }
        } else if (scenario == 'date-picker' || scenario == 'queued-date') {
          await tap(tester, '繼續草稿');
          final calendar = find.byTooltip('選擇日期');
          await tester.ensureVisible(calendar);
          await tester.pumpAndSettle();
          await tester.tap(calendar);
          await tester.pumpAndSettle();
          expect(find.byType(DatePickerDialog), findsOneWidget);
          await tester.tap(find.text('28').hitTestable());
          await tester.pumpAndSettle();
          if (scenario == 'queued-date') {
            tester
                .widget<TextButton>(find.widgetWithText(TextButton, '確定'))
                .onPressed!();
          }
        } else if (scenario == 'account') {
          await tap(tester, '繼續草稿');
          final dropdown = find.byType(DropdownButtonFormField<PublicId>);
          await tester.ensureVisible(dropdown);
          await tester.pumpAndSettle();
          await tester.tap(dropdown);
          await tester.pumpAndSettle();
          expect(find.text('保密現金 · TWD'), findsWidgets);
        } else {
          await tester.scrollUntilVisible(
            find.text('管理標籤'),
            180,
            scrollable: find.byType(Scrollable).first,
          );
          await tap(tester, '管理標籤');
          final menu = find.byTooltip('操作 保密標籤');
          await tester.ensureVisible(menu);
          await tester.pumpAndSettle();
          await tester.tap(menu);
          await tester.pumpAndSettle();
          expect(find.text('封存').hitTestable(), findsOneWidget);
        }

        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await tester.pump();
        // Active and already exiting routes are hidden on the first frame.
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.byType(DatePickerDialog), findsNothing);
        expect(find.text('保密現金 · TWD'), findsNothing);
        expect(find.text('封存'), findsNothing);
        for (final state in [
          AppLifecycleState.hidden,
          AppLifecycleState.paused,
          AppLifecycleState.hidden,
          AppLifecycleState.inactive,
          AppLifecycleState.resumed,
        ]) {
          tester.binding.handleAppLifecycleStateChanged(state);
        }
        await settle(tester);
        expect(find.widgetWithText(TextField, '密碼'), findsOneWidget);
        await input(tester, '密碼', password);
        await tap(tester, '解鎖');
        await tester.runAsync(() async {
          final restored = await engine.entryDraft();
          expect(restored?.id, saved!.id);
          expect(restored?.fields.amount, '12.50');
          expect(restored?.fields.date, '2026-09-27');
          expect((await engine.entries()).length, 1);
          expect(
            (await engine.accounts()).single.balance.minorUnits,
            BigInt.from(10000),
          );
          expect((await engine.tags()).get(tag).archived, isFalse);
        });
        await tap(tester, '繼續草稿');
        expect(
          tester
              .widget<TextField>(find.widgetWithText(TextField, '金額（正數）'))
              .controller!
              .text,
          '12.50',
        );
        expect(tester.takeException(), isNull);
      } finally {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpWidget(const SizedBox());
        await closeEngine(tester, engine);
        deleteSynthetic(work, root);
      }
    });
  }
}
