import 'dart:io';

import 'package:accounts/accounts.dart';
import 'package:credit_cards/credit_cards.dart';
import 'package:expense_preview/main.dart';
import 'package:expense_preview/preview_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';

import 'support.dart';
import 'widget_test.dart' show Documents, closeEngine, input, settle, tap;

Future<void> waitForSettings(WidgetTester tester, String version) async {
  for (var i = 0; i < 100; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump();
    if (find.text('目前版本：$version').evaluate().isNotEmpty) return;
  }
  throw StateError('Card settings did not load version $version');
}

void main() {
  testWidgets('card settings are private, validated, revised and reread', (
    tester,
  ) async {
    final root = Directory('.dart_tool/card-settings-widget-tests')
      ..createSync(recursive: true);
    final work = root.createTempSync('case-');
    final engine = engineAt(work, MemoryVault(), schemaVersion: 18);
    try {
      await tester.runAsync(() async {
        await setup(engine);
        final card = Account.open(
          id: PublicId.generate(),
          workspace: engine.workspace,
          name: '合成信用卡',
          kind: AccountKind.creditCard,
          currency: Currency('TWD', 2),
          openedOn: BusinessDate(2026, 9, 29),
        );
        await engine.createAccount(
          card,
          Posting.opening(
            id: PublicId.generate(),
            operation: OperationKey(
              engine.workspace,
              OperationId(PublicId.generate()),
            ),
            date: card.openedOn,
            account: ref(card),
            amount: Money(card.currency, BigInt.zero),
          ),
          cardTerms: CreditCardTerms(
            workspace: engine.workspace,
            cardId: card.id,
            currency: card.currency,
            closingDay: 30,
            dueDay: 15,
            limit: Money.parse(card.currency, '20000'),
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
      await tap(tester, '信用卡設定');
      if (find.byTooltip('隱藏金額').evaluate().isNotEmpty) {
        await tester.tap(find.byTooltip('隱藏金額'));
        await tester.pump();
      }
      expect(find.textContaining('目前已隱藏資料'), findsOneWidget);
      expect(find.byKey(const ValueKey('settings-limit')), findsNothing);
      await tester.tap(find.byTooltip('顯示金額'));
      await tester.pump();
      await waitForSettings(tester, '1');
      expect(find.textContaining('發卡行已確認帳單'), findsOneWidget);
      expect(find.text('合成信用卡 · TWD'), findsWidgets);

      await input(tester, '預定結帳日（1–31）', '0');
      await tap(tester, '儲存卡片設定');
      expect(find.textContaining('1–31 的整數'), findsOneWidget);
      expect(
        (await tester.runAsync(() => engine.savedCreditCards()))!
            .single
            .version,
        1,
      );

      await input(tester, '預定結帳日（1–31）', '28');
      await input(tester, '預定繳款日（1–31）', '12');
      await input(tester, '額度（可留空）', '');
      await tap(tester, '儲存卡片設定');
      await waitForSettings(tester, '2');
      final revised = (await tester.runAsync(() => engine.savedCreditCards()))!
          .single;
      expect(revised.closingDay, 28);
      expect(revised.dueDay, 12);
      expect(revised.limit, isNull);
      expect(revised.version, 2);

      await tester.tap(find.byTooltip('隱藏金額'));
      await tester.pump();
      expect(find.byKey(const ValueKey('settings-limit')), findsNothing);
      expect(find.text('目前版本：2'), findsNothing);
    } finally {
      await closeEngine(tester, engine);
      await tester.pumpWidget(const SizedBox());
      deleteSynthetic(work, root);
    }
  });
}
