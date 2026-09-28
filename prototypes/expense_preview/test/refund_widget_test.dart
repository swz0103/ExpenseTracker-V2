import 'dart:io';

import 'package:categories/categories.dart';
import 'package:expense_preview/main.dart';
import 'package:expense_preview/preview_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';

import 'support.dart';
import 'widget_test.dart' show Documents, settle, tap, input, closeEngine;

void main() {
  testWidgets(
    'partial refund raw draft resumes after lock; limits, full fill, original link and privacy work',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final semantics = tester.ensureSemantics();
      final root = Directory('.dart_tool/widget-tests')
            ..createSync(recursive: true),
          work = root.createTempSync('refund-');
      final engine = engineAt(work, MemoryVault(), schemaVersion: 10);
      late PublicId original;
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
        await visible(find.text(label));
        await tap(tester, label);
      }

      Future<void> enter(String label, String value) async {
        await visible(find.widgetWithText(TextField, label));
        await input(tester, label, value);
      }

      try {
        await tester.runAsync(() async {
          await setup(engine);
          final a = account(engine);
          await engine.createAccount(a, opening(a));
          final cat = PublicId.generate();
          OperationKey op() =>
              OperationKey(engine.workspace, OperationId(PublicId.generate()));
          await engine.createCategory(op(), cat, '原支出分類', CategoryKind.expense);
          final p = Posting.expense(
            id: PublicId.generate(),
            operation: op(),
            date: BusinessDate(2026, 9, 27),
            account: ref(a),
            amount: Money.parse(a.currency, '10'),
            allocations: [
              Allocation(
                cat,
                Money.parse(a.currency, '10'),
                expectedCategoryVersion: 1,
              ),
            ],
          );
          original = p.id;
          await engine.post(p);
          await engine.lock();
        });
        await tester.pumpWidget(
          PreviewApp(engine: Future.value(engine), documents: Documents()),
        );
        await settle(tester);
        await input(tester, '密碼', password);
        await tap(tester, '解鎖');
        final action = find.byKey(ValueKey('entry-actions-$original'));
        await visible(action);
        await tester.tap(action);
        await tester.pumpAndSettle();
        await tap(tester, '記錄退款');
        await enter('原幣退款金額（正數）', '2+');
        await tester.tap(find.byTooltip('鎖定'));
        await settle(tester);
        expect(find.text('記錄退款'), findsNothing);
        await input(tester, '密碼', password);
        await tap(tester, '解鎖');
        await button('繼續草稿');
        await visible(find.widgetWithText(TextField, '原幣退款金額（正數）'));
        expect(
          tester
              .widget<TextField>(find.widgetWithText(TextField, '原幣退款金額（正數）'))
              .controller!
              .text,
          '2+',
        );
        await enter('原幣退款金額（正數）', '11');
        await enter('分類退款金額 1（可為 0）', '11');
        await button('儲存退款');
        expect(find.text('退款超過原支出或該分類剩餘可退金額，請重新確認。'), findsOneWidget);
        await button('填入剩餘全額');
        await button('儲存退款');
        late PublicId refund;
        await tester.runAsync(() async {
          final rows = await engine.entries();
          expect(rows, hasLength(3));
          refund = rows.first.id;
          expect(rows.first.refundOf, original);
          expect(
            (await engine.accounts()).single.balance.minorUnits,
            BigInt.from(10000),
          );
          expect(await engine.entryDraft(), null);
        });
        await visible(find.byKey(ValueKey('refund-source-$refund')));
        await tester.tap(find.byTooltip('隱藏金額'));
        await settle(tester);
        await Scrollable.ensureVisible(
          tester.element(find.byKey(ValueKey('refund-source-$refund'))),
          alignment: 0.4,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ValueKey('refund-source-$refund')));
        await tester.pump(const Duration(milliseconds: 350));
        // Allow async DB read without waiting on the intentionally busy modal.
        for (
          var i = 0;
          i < 100 && find.byType(AlertDialog).evaluate().isEmpty;
          i++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 25)),
          );
          await tester.pump();
        }
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.text('TWD 10.00'), findsNothing);
        expect(find.bySemanticsLabel(RegExp('10[.]00')), findsNothing);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await settle(tester);
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.text('原支出分類'), findsNothing);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        expect(tester.takeException(), null);
      } finally {
        semantics.dispose();
        await tester.pumpWidget(const SizedBox());
        await closeEngine(tester, engine);
        deleteSynthetic(work, root);
      }
    },
  );
}
