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

void main() {
  final root = Directory('.dart_tool/card-refund-flow-tests')
    ..createSync(recursive: true);

  test(
    'cross-cycle card refund leaves confirmed bill intact through restore',
    () async {
      final work = root.createTempSync('source-');
      final vault = MemoryVault();
      PreviewEngine open() => engineAt(work, vault, schemaVersion: 19);
      var engine = open();
      try {
        final recoveryKey = await setup(engine);
        final currency = Currency('TWD', 2);
        final card = Account.open(
          id: PublicId.generate(),
          workspace: engine.workspace,
          name: 'Synthetic card',
          kind: AccountKind.creditCard,
          currency: currency,
          openedOn: BusinessDate(2026, 9, 1),
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
            amount: Money(currency, BigInt.zero),
          ),
          cardTerms: CreditCardTerms(
            workspace: engine.workspace,
            cardId: card.id,
            currency: currency,
            closingDay: 28,
            dueDay: 15,
          ),
        );
        await engine.saveEntryDraft(
          EntryFields(
            income: false,
            amount: '100',
            date: '2026-09-27',
            accountId: card.id,
          ),
        );
        await engine.submitEntryDraft();
        final purchase = (await engine.entries()).singleWhere(
          (entry) => entry.kind == PostingKind.expense,
        );
        final statementId = PublicId.generate();
        await engine.confirmCardStatement(
          statementId: statementId,
          cardId: card.id,
          revision: 1,
          cycle: CardCycle(
            startsAfter: BusinessDate(2026, 8, 28),
            closesOn: BusinessDate(2026, 9, 28),
            dueOn: BusinessDate(2026, 10, 15),
          ),
          billed: Money.parse(currency, '100'),
          operation: OperationId(PublicId.generate()),
        );
        await engine.saveEntryDraft(
          EntryFields(
            income: false,
            refundOf: purchase.id,
            accountId: card.id,
            amount: '25',
            date: '2026-10-02',
          ),
        );
        await engine.submitEntryDraft();
        expect(
          (await engine.refundStatus(purchase.id)).budget.remaining.majorText,
          '75.00',
        );
        expect(
          (await engine.accounts())
              .singleWhere((row) => row.account.id == card.id)
              .balance
              .majorText,
          '-75.00',
        );
        expect(
          (await engine.confirmedCardStatements(card.id))
              .single
              .remainingDue
              .majorText,
          '100.00',
        );
        final backup = await engine.exportBackup();
        for (final useRecovery in [false, true]) {
          final targetDir = root.createTempSync('restore-');
          final target = engineAt(targetDir, MemoryVault(), schemaVersion: 19);
          try {
            await setup(target);
            await target.importBackup(
              backup,
              useRecovery ? recoveryKey : password,
              recovery: useRecovery,
            );
            expect(
              (await target.refundStatus(purchase.id))
                  .budget
                  .remaining
                  .majorText,
              '75.00',
            );
            expect(
              (await target.confirmedCardStatements(card.id))
                  .single
                  .remainingDue
                  .majorText,
              '100.00',
            );
          } finally {
            await target.lock();
            deleteSynthetic(targetDir, root);
          }
        }
        await engine.lock();
        engine = open();
        await engine.unlock(password);
        expect(
          (await engine.refundStatus(purchase.id)).budget.remaining.majorText,
          '75.00',
        );
      } finally {
        await engine.lock();
        deleteSynthetic(work, root);
      }
    },
  );

  testWidgets('posted card purchase offers a refund to its original card', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final work = root.createTempSync('widget-');
    final engine = engineAt(work, MemoryVault(), schemaVersion: 19);
    late final Account card;
    late final PublicId purchaseId;
    try {
      await tester.runAsync(() async {
        await setup(engine);
        final currency = Currency('TWD', 2);
        card = Account.open(
          id: PublicId.generate(),
          workspace: engine.workspace,
          name: 'Synthetic refund card',
          kind: AccountKind.creditCard,
          currency: currency,
          openedOn: BusinessDate(2026, 9, 1),
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
            amount: Money(currency, BigInt.zero),
          ),
          cardTerms: CreditCardTerms(
            workspace: engine.workspace,
            cardId: card.id,
            currency: currency,
            closingDay: 28,
            dueDay: 15,
          ),
        );
        await engine.saveEntryDraft(
          EntryFields(
            income: false,
            amount: '20',
            date: '2026-09-27',
            accountId: card.id,
          ),
        );
        await engine.submitEntryDraft();
        purchaseId = (await engine.entries())
            .singleWhere((entry) => entry.kind == PostingKind.expense)
            .id;
        await engine.lock();
      });
      await tester.pumpWidget(
        PreviewApp(engine: Future.value(engine), documents: Documents()),
      );
      await settle(tester);
      await input(tester, '密碼', password);
      await tap(tester, '解鎖');
      final menu = find.byKey(ValueKey('entry-actions-$purchaseId'));
      if (menu.evaluate().isEmpty) {
        await tester.scrollUntilVisible(
          menu,
          180,
          scrollable: find.byType(Scrollable).first,
        );
      }
      await tester.ensureVisible(menu);
      await tester.tap(menu);
      await tester.pumpAndSettle();
      final refund = find.byWidgetPredicate(
        (widget) => widget is PopupMenuItem<String> && widget.value == 'refund',
      );
      expect(refund, findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is PopupMenuItem<String> &&
              [
                'reversal',
                'correction',
                'tombstone',
                'copy',
              ].contains(widget.value),
        ),
        findsNothing,
      );
      await tester.tap(refund);
      await settle(tester);
      expect(find.textContaining('Synthetic refund card'), findsWidgets);
      expect(find.byKey(ValueKey('refund-account-${card.id}')), findsNothing);
    } finally {
      await tester.pumpWidget(const SizedBox());
      await closeEngine(tester, engine);
      deleteSynthetic(work, root);
    }
  });
}
