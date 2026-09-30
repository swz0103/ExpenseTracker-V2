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
import 'widget_test.dart' show Documents, closeEngine, settle;

void main() {
  testWidgets('user reviews posted card purchase before saving a forecast', (
    tester,
  ) async {
    final root = Directory('.dart_tool/card-installment-widget-tests')
      ..createSync(recursive: true);
    final work = root.createTempSync('case-');
    final engine = engineAt(work, MemoryVault(), schemaVersion: 20);
    try {
      await tester.runAsync(() async {
        await setup(engine);
        final twd = Currency('TWD', 2);
        final card = Account.open(
          id: PublicId.generate(),
          workspace: engine.workspace,
          name: 'Synthetic card',
          kind: AccountKind.creditCard,
          currency: twd,
          openedOn: BusinessDate(2028, 1, 1),
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
            amount: Money(twd, BigInt.zero),
          ),
          cardTerms: CreditCardTerms(
            workspace: engine.workspace,
            cardId: card.id,
            currency: twd,
            closingDay: 31,
            dueDay: 15,
          ),
        );
        await engine.saveEntryDraft(
          EntryFields(
            income: false,
            amount: '100',
            date: '2028-02-20',
            accountId: card.id,
          ),
        );
        await engine.submitEntryDraft();
        await engine.lock();
      });
      await tester.pumpWidget(
        PreviewApp(engine: Future.value(engine), documents: Documents()),
      );
      await settle(tester);
      await tester.enterText(find.byType(TextField).first, password);
      await tester.tap(find.byType(FilledButton).first);
      await settle(tester);
      final open = find.byKey(const ValueKey('open-card-installments'));
      await tester.ensureVisible(open);
      await tester.tap(open);
      await tester.pump();
      for (var i = 0; i < 80; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
        await tester.pump();
        if (find.textContaining('100.00 TWD').evaluate().isNotEmpty) break;
      }
      final selector = find.byKey(const ValueKey('installment-purchase'));
      expect(selector, findsOneWidget);
      await tester.ensureVisible(selector);
      await tester.tap(selector);
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('100.00 TWD').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('installment-first-close')),
        '2028-02-29',
      );
      final review = find.byKey(const ValueKey('review-installment'));
      await tester.ensureVisible(review);
      await tester.tap(review);
      await tester.pump();
      expect(find.byKey(const ValueKey('save-installment')), findsOneWidget);
      final cardId = (await tester.runAsync(() => engine.accounts()))!
          .single
          .account
          .id;
      expect(
        (await tester.runAsync(
          () => engine.savedCardInstallmentPlans(cardId),
        ))!,
        isEmpty,
      );
      final save = find.byKey(const ValueKey('save-installment'));
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      await tester.tap(save);
      await settle(tester);
      expect(
        (await tester.runAsync(
          () => engine.savedCardInstallmentPlans(cardId),
        ))!,
        hasLength(1),
      );
      expect(
        (await tester.runAsync(() => engine.entries()))!
            .where((row) => row.kind == PostingKind.expense),
        hasLength(1),
      );
    } finally {
      await closeEngine(tester, engine);
      await tester.pumpWidget(const SizedBox());
      deleteSynthetic(work, root);
    }
  });

  testWidgets('a later refund is shown separately from the saved forecast', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final root = Directory('.dart_tool/card-installment-widget-refund-tests')
      ..createSync(recursive: true);
    final work = root.createTempSync('case-');
    final engine = engineAt(work, MemoryVault(), schemaVersion: 20);
    late final PublicId purchaseId;
    try {
      await tester.runAsync(() async {
        await setup(engine);
        final twd = Currency('TWD', 2);
        final card = Account.open(
          id: PublicId.generate(),
          workspace: engine.workspace,
          name: 'Refunded installment card',
          kind: AccountKind.creditCard,
          currency: twd,
          openedOn: BusinessDate(2028, 1, 1),
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
            amount: Money(twd, BigInt.zero),
          ),
          cardTerms: CreditCardTerms(
            workspace: engine.workspace,
            cardId: card.id,
            currency: twd,
            closingDay: 31,
            dueDay: 15,
          ),
        );
        await engine.saveEntryDraft(
          EntryFields(
            income: false,
            amount: '100',
            date: '2028-02-20',
            accountId: card.id,
          ),
        );
        await engine.submitEntryDraft();
        purchaseId = (await engine.availableInstallmentPurchases(card.id))
            .single
            .purchaseEventId;
        await engine.submitCardInstallmentPlan(
          CardInstallmentSchedule(
            purchaseEventId: purchaseId,
            workspace: engine.workspace,
            cardId: card.id,
            principal: Money.parse(twd, '99'),
            fixedFee: Money.parse(twd, '1'),
            firstScheduledClose: BusinessDate(2028, 2, 29),
            closingDay: 31,
            count: 3,
          ),
        );
        await engine.saveEntryDraft(
          EntryFields(
            income: false,
            refundOf: purchaseId,
            accountId: card.id,
            amount: '10',
            date: '2028-03-05',
          ),
        );
        await engine.submitEntryDraft();
        await engine.lock();
      });
      await tester.pumpWidget(
        PreviewApp(engine: Future.value(engine), documents: Documents()),
      );
      await settle(tester);
      await tester.enterText(find.byType(TextField).first, password);
      await tester.tap(find.byType(FilledButton).first);
      await settle(tester);
      final open = find.byKey(const ValueKey('open-card-installments'));
      await tester.ensureVisible(open);
      await tester.tap(open);
      for (var i = 0; i < 100; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
        await tester.pump();
        if (find.textContaining('退款後計畫需核對').evaluate().isNotEmpty) {
          break;
        }
      }
      expect(find.textContaining('已退 10.00 TWD'), findsOneWidget);
      expect(find.textContaining('不自動重算'), findsOneWidget);
      final activity = find.byKey(
        ValueKey('installment-refund-activity-$purchaseId'),
      );
      await tester.ensureVisible(activity);
      await tester.tap(activity);
      for (var i = 0; i < 100; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
        await tester.pump();
        if (find
            .byKey(ValueKey('activity-row-$purchaseId'))
            .evaluate()
            .isNotEmpty) {
          break;
        }
      }
      expect(find.text('交易活動'), findsOneWidget);
      expect(find.byKey(ValueKey('activity-row-$purchaseId')), findsOneWidget);
      await tester.tap(find.byTooltip('關閉活動'));
      await settle(tester);
    } finally {
      await tester.pumpWidget(const SizedBox());
      await closeEngine(tester, engine);
      deleteSynthetic(work, root);
    }
  });
}
