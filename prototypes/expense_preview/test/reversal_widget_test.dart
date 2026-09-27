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
    'reversal confirmation cancel and lock preserve raw draft; narrow large-text UI posts once',
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
          work = root.createTempSync('reversal-');
      final engine = engineAt(work, MemoryVault(), schemaVersion: 11);
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
        throw StateError('Reversal confirmation did not open');
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
        if (find.byTooltip('隱藏金額').evaluate().isNotEmpty) {
          await tester.tap(find.byTooltip('隱藏金額'));
          await settle(tester);
        }
        final action = find.byKey(ValueKey('entry-actions-$original'));
        await visible(action);
        await tester.tap(action);
        await tester.pumpAndSettle();
        await tap(tester, '撤銷交易');
        await enter('撤銷原因（選填）', '原輸入重複');
        await visible(find.text('撤銷這筆交易'));
        await tester.tap(find.text('撤銷這筆交易'));
        await dialogReady();
        expect(find.text('確認撤銷這筆交易？'), findsOneWidget);
        await tap(tester, '返回檢查');
        await tester.runAsync(() async {
          expect(await engine.entries(), hasLength(2));
        });
        await visible(find.text('撤銷這筆交易'));
        await tester.tap(find.text('撤銷這筆交易'));
        await dialogReady();
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await settle(tester);
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.text('原輸入重複'), findsNothing);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await input(tester, '密碼', password);
        await tap(tester, '解鎖');
        await button('繼續草稿');
        await visible(find.widgetWithText(TextField, '撤銷原因（選填）'));
        expect(
          tester
              .widget<TextField>(find.widgetWithText(TextField, '撤銷原因（選填）'))
              .controller!
              .text,
          '原輸入重複',
        );
        expect(find.bySemanticsLabel(RegExp('10[.]00')), findsNothing);
        await visible(find.text('撤銷這筆交易'));
        await tester.tap(find.text('撤銷這筆交易'));
        await dialogReady();
        await tester.tap(find.text('確認撤銷'));
        await settle(tester);
        await tester.runAsync(() async {
          final rows = await engine.entries();
          expect(rows, hasLength(3));
          expect(
            rows.singleWhere((e) => e.kind == PostingKind.reversal).reversalOf,
            original,
          );
          expect(
            rows.singleWhere((e) => e.id == original).reversedBy,
            isNotNull,
          );
          expect(
            (await engine.accounts()).single.balance.minorUnits,
            BigInt.from(10000),
          );
        });
        // Crypto work started by a widget can yield in the fake clock's zone.
        // Observe completion while advancing both real IO and widget frames.
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
            onError: (Object e) {
              draftError = e;
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
