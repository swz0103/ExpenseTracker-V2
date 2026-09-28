import 'dart:io';

import 'package:expense_preview/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';

import 'support.dart';
import 'widget_test.dart' show Documents, closeEngine, input, settle, tap;

void main() {
  testWidgets('search uses live ledger, masks money and clears on lock', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final root = Directory('.dart_tool/widget-tests')
      ..createSync(recursive: true);
    final work = root.createTempSync('search-');
    final engine = engineAt(work, MemoryVault(), schemaVersion: 12);
    late PublicId expenseId, incomeId;
    try {
      await tester.runAsync(() async {
        await setup(engine);
        final a = account(engine);
        await engine.createAccount(a, opening(a));
        final earned = income(a);
        incomeId = earned.id;
        await engine.post(earned);
        final spent = Posting.expense(
          id: PublicId.generate(),
          operation: OperationKey(
            engine.workspace,
            OperationId(PublicId.generate()),
          ),
          date: BusinessDate(2026, 9, 28),
          account: ref(a),
          amount: Money.parse(a.currency, '12.50'),
        );
        expenseId = spent.id;
        await engine.post(spent);
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
      await tap(tester, '搜尋交易');
      await input(tester, '開始日期（YYYY-MM-DD）', '2026-09-28');
      await input(tester, '結束日期（YYYY-MM-DD）', '2026-09-28');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('查詢'));
      await tester.pumpAndSettle();
      await tap(tester, '查詢');
      expect(
        find.byKey(ValueKey('search-result-${expenseId.value}')),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey('search-result-${incomeId.value}')),
        findsNothing,
      );
      expect(find.text('結果 1 筆'), findsOneWidget);
      expect(find.text('TWD -12.50'), findsNothing);
      expect(find.bySemanticsLabel(RegExp(r'交易金額已隱藏')), findsWidgets);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await settle(tester);
      expect(find.byKey(const Key('search-screen')), findsNothing);
      expect(
        find.byKey(ValueKey('search-result-${expenseId.value}')),
        findsNothing,
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await input(tester, '密碼', password);
      await tap(tester, '解鎖');
      await tap(tester, '搜尋交易');
      expect(find.text('結果 1 筆'), findsNothing);
      expect(tester.takeException(), null);
    } finally {
      await tester.pumpWidget(const SizedBox());
      await closeEngine(tester, engine);
      deleteSynthetic(work, root);
    }
  });
}
