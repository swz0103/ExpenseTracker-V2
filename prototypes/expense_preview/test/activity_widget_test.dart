import 'dart:io';

import 'package:expense_preview/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';

import 'support.dart';
import 'widget_test.dart' show Documents, settle, input, tap, closeEngine;

void main() {
  testWidgets(
    'activity pages from refund to original; narrow large-text privacy and lock hide all content',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final semantics = tester.ensureSemantics();
      final root = Directory('.dart_tool/widget-tests')
        ..createSync(recursive: true);
      final work = root.createTempSync('activity-');
      final engine = engineAt(work, MemoryVault(), schemaVersion: 10);
      late PublicId source, selected;
      Future<void> dialogReady() async {
        for (var i = 0; i < 200; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 25)),
          );
          await tester.pump();
          if (find.byType(Dialog).evaluate().isNotEmpty &&
              find
                  .descendant(
                    of: find.byType(Dialog),
                    matching: find.byType(CircularProgressIndicator),
                  )
                  .evaluate()
                  .isEmpty) {
            return;
          }
        }
        throw StateError('Activity did not finish loading');
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
            date: BusinessDate(2026, 9, 1),
            account: ref(a),
            amount: Money.parse(a.currency, '50'),
          );
          source = p.id;
          await engine.post(p);
          for (var i = 0; i < 31; i++) {
            final r = Posting.refund(
              id: PublicId.generate(),
              operation: OperationKey(
                engine.workspace,
                OperationId(PublicId.generate()),
              ),
              date: BusinessDate(2026, 9, 28),
              account: ref(a),
              originalId: p.id,
              amount: Money.parse(a.currency, '1'),
            );
            await engine.post(r);
            selected = r.id;
          }
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
        final menu = find.byKey(ValueKey('entry-actions-$selected'));
        await tester.scrollUntilVisible(
          menu,
          150,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.ensureVisible(menu);
        await tester.pump(const Duration(milliseconds: 350));
        await tester.tap(menu);
        await tester.pumpAndSettle();
        await tester.tap(find.text('查看活動'));
        await dialogReady();
        expect(find.text('交易活動'), findsOneWidget);
        expect(find.textContaining('記錄時間：'), findsWidgets);
        expect(find.bySemanticsLabel(RegExp(r'TWD.*[0-9]')), findsNothing);
        expect(find.text(source.value), findsNothing);
        final list = find.descendant(
          of: find.byKey(const Key('activity-list')),
          matching: find.byType(Scrollable),
        );
        final more = find.text('載入較早活動');
        await tester.scrollUntilVisible(
          more,
          400,
          scrollable: list,
          maxScrolls: 100,
        );
        await tester.ensureVisible(more);
        await tester.pump(const Duration(milliseconds: 350));
        await tester.tap(more);
        await dialogReady();
        final original = find.byKey(ValueKey('activity-row-$source'));
        await tester.scrollUntilVisible(
          original,
          200,
          scrollable: list,
          maxScrolls: 30,
        );
        expect(find.text('交易日期：2026-09-01'), findsOneWidget);
        expect(find.text('TWD -50.00'), findsNothing);
        expect(tester.takeException(), null);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await settle(tester);
        expect(find.byType(Dialog), findsNothing);
        expect(find.textContaining('記錄時間：'), findsNothing);
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
