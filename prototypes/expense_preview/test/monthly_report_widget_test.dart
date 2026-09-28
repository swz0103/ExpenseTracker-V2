import 'dart:io';

import 'package:expense_preview/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';

import 'support.dart';
import 'widget_test.dart' show Documents, closeEngine, input, settle, tap;

void main() {
  testWidgets('an empty current month can open an older nonempty report', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final root = Directory('.dart_tool/widget-tests')
      ..createSync(recursive: true);
    final work = root.createTempSync('monthly-empty-');
    final engine = engineAt(work, MemoryVault(), schemaVersion: 12);
    try {
      await tester.runAsync(() async {
        await setup(engine);
        final a = account(engine);
        await engine.createAccount(a, opening(a));
        final now = DateTime.now();
        final previous = DateTime(now.year, now.month, 0);
        await engine.post(
          Posting.income(
            id: PublicId.generate(),
            operation: OperationKey(
              engine.workspace,
              OperationId(PublicId.generate()),
            ),
            date: BusinessDate(previous.year, previous.month, 1),
            account: ref(a),
            amount: Money.parse(a.currency, '12'),
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
      expect(find.text('本月尚無收入或支出。'), findsOneWidget);
      await tap(tester, '查看月收支明細');
      expect(find.text('這個月沒有影響收入或支出的交易。'), findsOneWidget);
      await tap(tester, '上個月');
      expect(find.text('TWD 12.00'), findsWidgets);
      expect(tester.takeException(), null);
    } finally {
      await tester.pumpWidget(const SizedBox());
      await closeEngine(tester, engine);
      deleteSynthetic(work, root);
    }
  });

  testWidgets('monthly totals drill to entries, mask and disappear on lock', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final root = Directory('.dart_tool/widget-tests')
      ..createSync(recursive: true);
    final work = root.createTempSync('monthly-');
    final engine = engineAt(work, MemoryVault(), schemaVersion: 12);
    try {
      await tester.runAsync(() async {
        await setup(engine);
        final a = account(engine);
        await engine.createAccount(a, opening(a));
        final now = DateTime.now();
        final day = BusinessDate(now.year, now.month, 1);
        await engine.post(
          Posting.income(
            id: PublicId.generate(),
            operation: OperationKey(
              engine.workspace,
              OperationId(PublicId.generate()),
            ),
            date: day,
            account: ref(a),
            amount: Money.parse(a.currency, '100'),
          ),
        );
        await engine.post(
          Posting.expense(
            id: PublicId.generate(),
            operation: OperationKey(
              engine.workspace,
              OperationId(PublicId.generate()),
            ),
            date: day,
            account: ref(a),
            amount: Money.parse(a.currency, '40'),
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
        find.text('本月收支'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('本月收支'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('TWD 100.00'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('TWD 100.00'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('TWD 40.00'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('TWD 40.00'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('查看月收支明細'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tap(tester, '查看月收支明細');
      expect(find.byKey(const Key('monthly-report-screen')), findsOneWidget);
      expect(find.text('TWD 60.00'), findsOneWidget);
      expect(find.text('明細'), findsOneWidget);
      expect(find.text('查看活動'), findsNWidgets(2));
      await tap(tester, '上個月');
      expect(find.text('這個月沒有影響收入或支出的交易。'), findsOneWidget);
      await tap(tester, '下個月');
      expect(find.text('TWD 60.00'), findsOneWidget);
      await tester.tap(find.byTooltip('隱藏金額'));
      await settle(tester);
      expect(find.text('TWD 60.00'), findsNothing);
      expect(find.bySemanticsLabel(RegExp(r'交易金額已隱藏')), findsWidgets);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await settle(tester);
      expect(find.byKey(const Key('monthly-report-screen')), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await input(tester, '密碼', password);
      await tap(tester, '解鎖');
      expect(find.byKey(const Key('monthly-report-screen')), findsNothing);
      expect(tester.takeException(), null);
    } finally {
      await tester.pumpWidget(const SizedBox());
      await closeEngine(tester, engine);
      deleteSynthetic(work, root);
    }
  });
}
