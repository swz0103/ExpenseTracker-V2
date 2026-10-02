import 'dart:io';

import 'package:accounts/accounts.dart';
import 'package:expense_preview/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';

import 'support.dart';
import 'widget_test.dart' show Documents, closeEngine, input, settle, tap;

void main() {
  Posting openingAmount(Account value, String amount) => Posting.opening(
    id: PublicId.generate(),
    operation: OperationKey(value.workspace, OperationId(PublicId.generate())),
    date: value.openedOn,
    account: ref(value),
    amount: Money.parse(value.currency, amount),
  );

  testWidgets('account lifecycle is operable with close protections', (
    tester,
  ) async {
    final root = Directory('.dart_tool/widget-tests')
      ..createSync(recursive: true);
    final work = root.createTempSync('account-lifecycle-');
    final engine = engineAt(work, MemoryVault(), schemaVersion: 24);
    try {
      await tester.runAsync(() async {
        await setup(engine);
        final zero = account(engine, name: 'Zero cash');
        final funded = account(engine, name: 'Funded bank');
        await engine.createAccount(zero, openingAmount(zero, '0'));
        await engine.createAccount(funded, openingAmount(funded, '10'));
        await engine.lock();
      });
      await tester.pumpWidget(
        PreviewApp(engine: Future.value(engine), documents: Documents()),
      );
      await settle(tester);
      await input(tester, '密碼', password);
      await tap(tester, '解鎖');
      await tester.tap(find.byTooltip('設定'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('帳戶管理'));
      await settle(tester);
      expect(
        find.byKey(const ValueKey('account-management-screen')),
        findsOneWidget,
      );

      await tester.tap(find.byTooltip('管理 Zero cash'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('改名'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, '新名稱'), 'Daily');
      await tester.tap(find.text('儲存名稱'));
      await settle(tester);
      expect(find.text('Daily'), findsOneWidget);

      await tester.tap(find.byTooltip('管理 Daily'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('從資產摘要排除'));
      await settle(tester);
      expect(find.textContaining('不納入摘要'), findsOneWidget);

      await tester.tap(find.byTooltip('管理 Daily'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('封存'));
      await tester.pumpAndSettle();
      expect(find.textContaining('不會釋放 32 個帳戶上限'), findsOneWidget);
      await tester.tap(find.text('確認封存'));
      await settle(tester);
      expect(find.textContaining('已封存'), findsWidgets);

      await tester.tap(find.byTooltip('管理 Daily'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('重新啟用'));
      await settle(tester);
      expect(find.textContaining('使用中'), findsWidgets);

      await tester.tap(find.byTooltip('管理 Funded bank'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('關閉帳戶'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, '關閉原因'),
        'No longer needed',
      );
      await tester.tap(find.text('確認關閉'));
      await settle(tester);
      expect(find.text('餘額必須為零才能關閉帳戶。'), findsOneWidget);

      await tester.tap(find.byTooltip('管理 Daily'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('關閉帳戶'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, '關閉原因'),
        'Moved away',
      );
      await tester.tap(find.text('確認關閉'));
      await settle(tester);
      expect(find.textContaining('已關閉'), findsWidgets);
      expect(find.textContaining('Moved away'), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox());
      await closeEngine(tester, engine);
      deleteSynthetic(work, root);
    }
  });
}
