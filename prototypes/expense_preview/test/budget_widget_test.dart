import 'dart:io';

import 'package:expense_preview/main.dart';
import 'package:expense_preview/preview_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';

import 'support.dart';
import 'widget_test.dart' show Documents, closeEngine, input, settle, tap;

void main() {
  testWidgets(
    'monthly budget create, update, cancel and remove use saved facts',
    (tester) async {
      final root = Directory('.dart_tool/budget-widget-tests')
        ..createSync(recursive: true);
      final work = root.createTempSync('case-');
      final engine = engineAt(work, MemoryVault(), schemaVersion: 15);
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
        if (find.byTooltip('顯示金額').evaluate().isNotEmpty) {
          await tester.tap(find.byTooltip('顯示金額'));
          await settle(tester);
        }
        expect(engine.isUnlocked, isTrue);
        await tester.scrollUntilVisible(find.text('月預算'), 300);
        await tap(tester, '月預算');
        await input(tester, '預算上限', '20');
        await tap(tester, '保存預算');
        expect(find.text('TWD 3.00'), findsWidgets);
        expect(find.text('TWD 17.00'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('返回帳本'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tap(tester, '返回帳本');
        expect(find.text('全部支出'), findsOneWidget);
        expect(find.text('TWD 3.00 / TWD 20.00'), findsOneWidget);
        await tester.scrollUntilVisible(find.text('月預算'), 300);
        await tap(tester, '月預算');
        await tap(tester, '修改');
        await tester.ensureVisible(find.text('取消修改'));
        await tester.tap(find.text('取消修改'));
        await tester.pump();
        expect(find.text('TWD 17.00'), findsOneWidget);
        await tester.ensureVisible(find.text('修改'));
        await tester.tap(find.text('修改'));
        await tester.pump();
        await input(tester, '預算上限', 'invalid');
        await tap(tester, '保存修改');
        expect(find.text('預算未保存。請檢查金額、月份與條件後重試。'), findsOneWidget);
        expect(
          (await tester.runAsync(() => engine.savedBudgets()))!
              .single
              .limit
              .majorText,
          '20.00',
        );
        await input(tester, '預算上限', '5');
        await tap(tester, '保存修改');
        expect(find.text('TWD 2.00'), findsOneWidget);
        await tester.ensureVisible(find.text('刪除'));
        await tester.tap(find.text('刪除'));
        await tester.pump();
        await tester.tap(find.text('取消'));
        await tester.pump();
        expect(find.text('TWD 2.00'), findsOneWidget);
        await tester.ensureVisible(find.text('刪除'));
        await tester.tap(find.text('刪除'));
        await tester.pump();
        await tester.tap(find.text('確認刪除'));
        await settle(tester);
        expect(find.text('TWD 2.00'), findsNothing);
        expect(await engine.savedBudgets(), isEmpty);
        await tester.tap(find.byTooltip('隱藏金額'));
        await settle(tester);
        expect(find.text('TWD 3.00'), findsNothing);
        expect(find.text('先顯示金額，才能設定預算。'), findsOneWidget);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await closeEngine(tester, engine);
        deleteSynthetic(work, root);
      }
    },
  );
}
