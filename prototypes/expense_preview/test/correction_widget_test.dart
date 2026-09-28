import 'dart:io';

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
    'narrow correction screen confirms once and masks original amount',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final semantics = tester.ensureSemantics();
      final root = Directory('.dart_tool/widget-tests')
        ..createSync(recursive: true);
      final work = root.createTempSync('correction-');
      final engine = engineAt(work, MemoryVault(), schemaVersion: 13);
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

      Future<void> dialogReady() async {
        for (var i = 0; i < 100; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 25)),
          );
          await tester.pump();
          if (find.byType(AlertDialog).evaluate().isNotEmpty) {
            await tester.pump(const Duration(milliseconds: 350));
            return;
          }
        }
        throw StateError('Correction confirmation did not open');
      }

      try {
        await tester.runAsync(() async {
          await setup(engine);
          final a = account(engine);
          await engine.createAccount(a, opening(a));
          final p = Posting.expense(
            id: PublicId.generate(),
            operation: OperationKey(
              engine.workspace,
              OperationId(PublicId.generate()),
            ),
            date: BusinessDate(2026, 9, 28),
            account: ref(a),
            amount: Money.parse(a.currency, '10'),
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
        await tap(tester, '更正交易');
        await visible(find.text('替代交易'));
        expect(find.bySemanticsLabel(RegExp('10[.]00')), findsNothing);
        await visible(find.widgetWithText(TextField, '金額（正數）'));
        await input(tester, '金額（正數）', '7');
        await visible(find.text('送出更正'));
        await tester.tap(find.text('送出更正'));
        await dialogReady();
        expect(find.text('確認更正這筆交易？'), findsOneWidget);
        await tap(tester, '返回檢查');
        await tester.runAsync(() async {
          expect(await engine.entries(), hasLength(2));
        });
        await visible(find.text('送出更正'));
        await tester.tap(find.text('送出更正'));
        await dialogReady();
        await tap(tester, '確認更正');
        await settle(tester);
        await tester.runAsync(() async {
          expect(await engine.entries(), hasLength(4));
          expect(
            (await engine.accounts()).single.balance.minorUnits,
            BigInt.from(9300),
          );
        });
        var checkedDraft = false;
        Object? draftError;
        await tester.runAsync(() async {
          engine.entryDraft().then(
            (draft) {
              if (draft != null) {
                draftError = StateError('Consumed draft remains');
              }
              checkedDraft = true;
            },
            onError: (Object error) {
              draftError = error;
              checkedDraft = true;
            },
          );
        });
        for (var i = 0; !checkedDraft && i < 200; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 25)),
          );
          await tester.pump();
        }
        expect(checkedDraft, true);
        expect(draftError, null);
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
