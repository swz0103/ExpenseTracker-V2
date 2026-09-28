import 'dart:io';

import 'package:expense_preview/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';

import 'support.dart';
import 'widget_test.dart' show Documents, closeEngine, input, settle, tap;

void main() {
  testWidgets('account report remains usable at 320px and double text size', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final root = Directory('.dart_tool/widget-tests')
      ..createSync(recursive: true);
    final work = root.createTempSync('account-report-');
    final engine = engineAt(work, MemoryVault(), schemaVersion: 12);
    try {
      await tester.runAsync(() async {
        await setup(engine);
        final cash = account(engine);
        await engine.createAccount(cash, opening(cash));
        final now = DateTime.now();
        await engine.post(
          Posting.expense(
            id: PublicId.generate(),
            operation: OperationKey(
              engine.workspace,
              OperationId(PublicId.generate()),
            ),
            date: BusinessDate(now.year, now.month, 1),
            account: ref(cash),
            amount: Money.parse(cash.currency, '3'),
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
      await tester.scrollUntilVisible(
        find.text('查看月收支明細'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tap(tester, '查看月收支明細');
      await tap(tester, '帳戶');
      expect(find.textContaining('帳戶幣別 TWD'), findsOneWidget);
      await tap(tester, '查看帳戶明細');
      expect(find.text('TWD 3.00'), findsWidgets);
      await tester.tap(find.byTooltip('隱藏金額'));
      await settle(tester);
      expect(find.text('TWD 3.00'), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await settle(tester);
      expect(find.byKey(const Key('monthly-report-screen')), findsNothing);
    } finally {
      await tester.pumpWidget(const SizedBox());
      await closeEngine(tester, engine);
      deleteSynthetic(work, root);
    }
  });
}
