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
    'narrow deletion confirmation cancels cleanly, then retains private history',
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
      final work = root.createTempSync('tombstone-');
      final engine = engineAt(work, MemoryVault(), schemaVersion: 14);
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
        throw StateError('Deletion confirmation did not open');
      }

      Future<void> openDeletion() async {
        final action = find.byKey(ValueKey('entry-actions-$original'));
        await visible(action);
        await tester.tap(action);
        await tester.pumpAndSettle();
        await tester.tap(find.text('刪除交易').last);
        await tester.pump();
        await dialogReady();
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
        if (find.byTooltip('隱藏金額').evaluate().isNotEmpty) {
          await tester.tap(find.byTooltip('隱藏金額'));
          await settle(tester);
        }
        await openDeletion();
        expect(find.text('刪除這筆交易？'), findsOneWidget);
        expect(find.bySemanticsLabel(RegExp('10[.]00')), findsNothing);
        await tap(tester, '取消');
        await tester.runAsync(() async {
          expect(
            (await engine.accounts()).single.balance.minorUnits,
            BigInt.from(9000),
          );
          expect(await engine.entryDraft(), isNull);
        });

        await openDeletion();
        await input(tester, '刪除原因（可留空）', '重複記錄');
        await tap(tester, '確認刪除');
        await settle(tester);
        await tester.runAsync(() async {
          expect(
            (await engine.accounts()).single.balance.minorUnits,
            BigInt.from(10000),
          );
          expect(await engine.entries(), hasLength(1));
          expect((await engine.deletedEntries()).single.id, original);
        });
        await visible(find.byKey(ValueKey('deleted-entry-$original')));
        expect(find.text('原因已隱藏'), findsOneWidget);
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
