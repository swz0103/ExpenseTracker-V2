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
  testWidgets(
    'split rows recover raw text after lock, reject wrong total, submit and mask every detail',
    (tester) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final semantics = tester.ensureSemantics();
      final root = Directory('.dart_tool/widget-tests')
        ..createSync(recursive: true);
      final work = root.createTempSync('split-');
      final engine = engineAt(work, MemoryVault(), schemaVersion: 9);
      Future<void> visible(Finder f) async {
        if (f.evaluate().isEmpty) {
          await tester.scrollUntilVisible(
            f,
            180,
            scrollable: find.byType(Scrollable).first,
          );
        }
        await tester.ensureVisible(f);
        await tester.pumpAndSettle();
      }

      Future<void> button(String label) async {
        await visible(find.text(label).first);
        await tap(tester, label);
      }

      Future<void> enter(String label, String text) async {
        await visible(find.widgetWithText(TextField, label));
        await input(tester, label, text);
      }

      Future<void> choose(String label, String value) async {
        final f = find.widgetWithText(DropdownButtonFormField<PublicId>, label);
        await visible(f);
        await tester.tap(f);
        await tester.pumpAndSettle();
        await tester.tap(find.text(value).last);
        await tester.pumpAndSettle();
        await settle(tester);
      }

      Future<String> value(String label) async {
        final f = find.widgetWithText(TextField, label);
        await visible(f);
        return tester.widget<TextField>(f).controller!.text;
      }

      try {
        await tester.runAsync(() async {
          await setup(engine);
          final a = account(engine);
          await engine.createAccount(a, opening(a));
          for (final name in ['餐飲', '交通']) {
            await engine.createCategory(
              OperationKey(engine.workspace, OperationId(PublicId.generate())),
              PublicId.generate(),
              name,
              CategoryKind.expense,
            );
          }
          await engine.lock();
        });
        await tester.pumpWidget(
          PreviewApp(engine: Future.value(engine), documents: Documents()),
        );
        await settle(tester);
        await input(tester, '密碼', password);
        await tap(tester, '解鎖');
        await button('記一筆');
        await enter('金額（正數）', '10');
        await button('拆分多個分類');
        await choose('拆分分類 1', '餐飲');
        await enter('拆分金額 1', '3.25');
        await choose('拆分分類 2', '交通');
        await enter('拆分金額 2', '6+');
        await tester.tap(find.byTooltip('鎖定'));
        await settle(tester);
        expect(find.widgetWithText(TextField, '拆分金額 1'), findsNothing);
        await input(tester, '密碼', password);
        await tap(tester, '解鎖');
        await button('繼續草稿');
        expect(await value('拆分金額 1'), '3.25');
        expect(await value('拆分金額 2'), '6+');
        await enter('拆分金額 2', '6.74');
        await button('儲存收支');
        expect(find.text('拆分合計必須等於交易總額；請確認各項金額。'), findsOneWidget);
        await enter('拆分金額 2', '6.75');
        await visible(find.byKey(const Key('split-total')));
        expect(find.text('拆分合計 TWD 10.00 · 差額 TWD 0.00'), findsOneWidget);
        await button('儲存收支');
        late PublicId event;
        await tester.runAsync(() async {
          final rows = await engine.entries();
          expect(rows.length, 2);
          event = rows.first.id;
          expect(
            (await engine.accounts()).single.balance.minorUnits,
            BigInt.from(9000),
          );
        });
        await visible(find.textContaining('拆分 2 個分類'));
        expect(find.text('TWD 3.25'), findsOneWidget);
        expect(find.text('TWD 6.75'), findsOneWidget);
        await tester.tap(find.byTooltip('隱藏金額'));
        await settle(tester);
        expect(find.text('TWD 3.25'), findsNothing);
        expect(find.text('TWD 6.75'), findsNothing);
        expect(find.bySemanticsLabel(RegExp('3[.]25|6[.]75')), findsNothing);
        final action = find.byKey(ValueKey('entry-actions-$event'));
        await visible(action);
        await tester.tap(action);
        await tester.pumpAndSettle();
        await tap(tester, '再記一筆類似交易');
        expect(await value('金額（正數）'), '');
        expect(await value('日期（YYYY-MM-DD）'), '');
        expect(await value('拆分金額 1'), '');
        expect(await value('拆分金額 2'), '');
        // Row add/remove must dispose fields after detachment, preserving other input.
        await enter('拆分金額 1', '1');
        await button('增加拆分');
        await enter('拆分金額 3', '2');
        await button('移除拆分 3');
        expect(await value('拆分金額 1'), '1');
        expect(find.widgetWithText(TextField, '拆分金額 3'), findsNothing);
        await tester.tap(find.byTooltip('鎖定'));
        await settle(tester);
        expect(find.text('餐飲'), findsNothing);
        expect(tester.takeException(), null);
      } finally {
        semantics.dispose();
        await tester.pumpWidget(const SizedBox());
        await closeEngine(tester, engine);
        deleteSynthetic(work, root);
      }
    },
  );
  testWidgets(
    'duplicate draft choices need reselection and lock dismisses split category popup at large font',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final root = Directory('.dart_tool/widget-tests')
            ..createSync(recursive: true),
          work = root.createTempSync('split-popup-');
      final engine = engineAt(work, MemoryVault(), schemaVersion: 9);
      late PublicId category;
      try {
        await tester.runAsync(() async {
          await setup(engine);
          final a = account(engine);
          await engine.createAccount(a, opening(a));
          category = PublicId.generate();
          await engine.createCategory(
            OperationKey(engine.workspace, OperationId(PublicId.generate())),
            category,
            '私人分類',
            CategoryKind.expense,
          );
          await engine.saveEntryDraft(
            EntryFields(
              income: false,
              split: true,
              amount: '10',
              date: '2026-09-28',
              accountId: a.id,
              splits: [
                SplitFields(categoryId: category, amount: '3.25'),
                SplitFields(categoryId: category, amount: '6.75'),
              ],
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
        await tap(tester, '繼續草稿');
        final second = find.widgetWithText(
          DropdownButtonFormField<PublicId>,
          '拆分分類 2',
        );
        await tester.scrollUntilVisible(
          second,
          180,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(
          tester.widget<DropdownButtonFormField<PublicId>>(second).initialValue,
          null,
        );
        final first = find.widgetWithText(
          DropdownButtonFormField<PublicId>,
          '拆分分類 1',
        );
        await tester.scrollUntilVisible(
          first,
          -180,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(first);
        await tester.tap(first);
        await tester.pumpAndSettle();
        expect(find.byType(DropdownButton<PublicId>), findsWidgets);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await settle(tester);
        expect(find.text('私人分類'), findsNothing);
        expect(find.widgetWithText(TextField, '拆分金額 1'), findsNothing);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        expect(tester.takeException(), null);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await closeEngine(tester, engine);
        deleteSynthetic(work, root);
      }
    },
  );
}
