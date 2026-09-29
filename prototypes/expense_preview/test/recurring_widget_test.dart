import 'dart:io';

import 'package:expense_preview/main.dart';
import 'package:expense_preview/preview_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';
import 'widget_test.dart' show Documents, closeEngine, input, settle, tap;

void main() {
  testWidgets('recurring candidate needs confirmation and never posts twice', (
    tester,
  ) async {
    final root = Directory('.dart_tool/recurring-widget-tests')
      ..createSync(recursive: true);
    final work = root.createTempSync('case-');
    final engine = engineAt(work, MemoryVault(), schemaVersion: 16);
    try {
      await tester.runAsync(() async {
        await setup(engine);
        final cash = account(engine);
        await engine.createAccount(cash, opening(cash));
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
      await tester.scrollUntilVisible(find.text('定期交易'), 300);
      await tap(tester, '定期交易');
      await input(tester, '名稱', '房租');
      await input(tester, '每期金額', '10');
      await tap(tester, '建立模板');
      expect(find.text('確認入帳'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('返回帳本'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tap(tester, '返回帳本');
      await tester.scrollUntilVisible(find.text('定期交易'), 300);
      for (
        var i = 0;
        i < 100 && find.text('有 1 筆定期交易待確認。').evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
        await tester.pump();
      }
      expect(find.text('有 1 筆定期交易待確認。'), findsOneWidget);
      await tester.tap(find.byTooltip('隱藏金額'));
      await settle(tester);
      expect(find.text('有定期交易待確認。'), findsOneWidget);
      expect(find.text('有 1 筆定期交易待確認。'), findsNothing);
      await tester.tap(find.byTooltip('顯示金額'));
      await settle(tester);
      await tap(tester, '定期交易');
      expect((await tester.runAsync(() => engine.entries()))!, hasLength(1));

      await tap(tester, '確認入帳');
      await tester.tap(find.text('取消'));
      await settle(tester);
      expect((await tester.runAsync(() => engine.entries()))!, hasLength(1));

      await tap(tester, '確認入帳');
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('確認入帳'),
        ),
      );
      await settle(tester);
      expect((await tester.runAsync(() => engine.entries()))!, hasLength(2));
      expect(find.text('目前查詢範圍沒有待確認項目。'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('返回帳本'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tap(tester, '返回帳本');
      await tester.scrollUntilVisible(find.text('定期交易'), 300);
      await tap(tester, '定期交易');
      expect(find.text('目前查詢範圍沒有待確認項目。'), findsOneWidget);
      expect(find.text('有 1 筆定期交易待確認。'), findsNothing);
      expect((await tester.runAsync(() => engine.entries()))!, hasLength(2));

      await tap(tester, '修改');
      await input(tester, '每期金額', '12');
      await tap(tester, '保存修改');
      expect(
        (await tester.runAsync(() => engine.savedRecurringTemplates()))!
            .single
            .amount
            .majorText,
        '-12.00',
      );
      expect((await tester.runAsync(() => engine.entries()))!, hasLength(2));
      await tester.scrollUntilVisible(
        find.text('停用'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('停用'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('確認停用'));
      await settle(tester);
      expect(
        await tester.runAsync(() => engine.savedRecurringTemplates()),
        isEmpty,
      );
      expect((await tester.runAsync(() => engine.entries()))!, hasLength(2));
    } finally {
      await tester.pumpWidget(const SizedBox());
      await closeEngine(tester, engine);
      deleteSynthetic(work, root);
    }
  });
}
