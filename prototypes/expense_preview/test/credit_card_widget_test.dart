import 'dart:io';

import 'package:accounts/accounts.dart';
import 'package:expense_preview/main.dart';
import 'package:expense_preview/preview_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/ledger.dart';

import 'support.dart';
import 'widget_test.dart' show Documents, closeEngine, input, settle, tap;

void main() {
  testWidgets('user creates a card with saved billing settings', (
    tester,
  ) async {
    final root = Directory('.dart_tool/card-widget-tests')
      ..createSync(recursive: true);
    final work = root.createTempSync('case-');
    final engine = engineAt(work, MemoryVault(), schemaVersion: 17);
    try {
      await tester.runAsync(() async {
        await setup(engine);
        await engine.lock();
      });
      await tester.pumpWidget(
        PreviewApp(engine: Future.value(engine), documents: Documents()),
      );
      await settle(tester);
      await input(tester, '密碼', password);
      await tap(tester, '解鎖');
      await tap(tester, '新增帳戶');
      await input(tester, '帳戶名稱', '合成信用卡');
      final kind = find.byType(DropdownButtonFormField<AccountKind>);
      await tester.ensureVisible(kind);
      await tester.pumpAndSettle();
      await tester.tap(kind);
      await tester.pumpAndSettle();
      await tester.tap(find.text('信用卡').last);
      await tester.pumpAndSettle();
      await input(tester, '結帳日（1–31）', '28');
      await input(tester, '繳款日（1–31）', '12');
      await input(tester, '額度（可留空）', '20000');
      await input(tester, '起始日期（YYYY-MM-DD）', '2026-09-29');
      await tap(tester, '建立帳戶');
      final accounts = (await tester.runAsync(() => engine.accounts()))!;
      expect(accounts.single.account.kind, AccountKind.creditCard);
      expect(accounts.single.balance.minorUnits, BigInt.zero);
      final terms = (await tester.runAsync(() => engine.savedCreditCards()))!;
      expect(terms.single.closingDay, 28);
      expect(terms.single.dueDay, 12);
      expect(terms.single.limit?.majorText, '20000.00');
      expect(find.byKey(const ValueKey('asset-total-TWD')), findsNothing);
      await tap(tester, '信用卡刷卡入帳');
      await input(tester, '實際入帳金額', '123.45');
      await tap(tester, '確認刷卡入帳');
      final after = (await tester.runAsync(() => engine.accounts()))!;
      expect(after.single.balance.minorUnits, BigInt.from(-12345));
      final entries = (await tester.runAsync(() => engine.entries()))!;
      final purchase = entries.singleWhere(
        (entry) => entry.kind == PostingKind.expense,
      );
      expect(purchase.accountId, after.single.account.id);
      expect(purchase.amount.minorUnits, BigInt.from(-12345));
    } finally {
      await closeEngine(tester, engine);
      await tester.pumpWidget(const SizedBox());
      deleteSynthetic(work, root);
    }
  });
}
