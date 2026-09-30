import 'dart:io';

import 'package:accounts/accounts.dart';
import 'package:credit_cards/credit_cards.dart';
import 'package:expense_preview/preview_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';

import 'support.dart';

void main() {
  final root = Directory('.dart_tool/card-installment-flow-tests')
    ..createSync(recursive: true);

  test(
    'ambiguous installment save replays without another Ledger expense',
    () async {
      final work = root.createTempSync('case-');
      final vault = MemoryVault();
      var loseAcknowledgement = true;
      PreviewEngine open() => engineAt(
        work,
        vault,
        schemaVersion: 20,
        draftCheckpoint: (point) {
          if (point == 'card-installment-committed' && loseAcknowledgement) {
            loseAcknowledgement = false;
            throw StateError('synthetic acknowledgement loss');
          }
        },
      );
      var engine = open();
      try {
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
            amount: '101.02',
            date: '2028-02-20',
            accountId: card.id,
          ),
        );
        await engine.submitEntryDraft();
        final purchase = (await engine.availableInstallmentPurchases(card.id))
            .single;
        expect(purchase.amount.majorText, '101.02');
        final before = await engine.entries();
        final plan = CardInstallmentSchedule(
          purchaseEventId: purchase.purchaseEventId,
          workspace: engine.workspace,
          cardId: card.id,
          principal: Money.parse(twd, '100.01'),
          fixedFee: Money.parse(twd, '1.01'),
          firstScheduledClose: BusinessDate(2028, 2, 29),
          closingDay: 31,
          count: 3,
        );
        await expectLater(
          engine.submitCardInstallmentPlan(plan),
          throwsA(isA<StateError>()),
        );
        expect(await engine.hasPendingInstallmentPlan(), isTrue);
        expect(await engine.savedCardInstallmentPlans(card.id), hasLength(1));
        await engine.lock();
        engine = open();
        await engine.unlock(password);
        await engine.retryPendingInstallmentPlan();
        await engine.submitCardInstallmentPlan(plan);
        expect(await engine.hasPendingInstallmentPlan(), isFalse);
        expect(await engine.savedCardInstallmentPlans(card.id), hasLength(1));
        expect(await engine.availableInstallmentPurchases(card.id), isEmpty);
        expect((await engine.entries()).length, before.length);
        expect((await engine.accounts()).single.balance.majorText, '-101.02');
        await engine.saveEntryDraft(
          EntryFields(
            income: false,
            refundOf: purchase.purchaseEventId,
            accountId: card.id,
            amount: '10',
            date: '2028-03-05',
          ),
        );
        await engine.submitEntryDraft();
        final refunded = (await engine.savedCardInstallmentPlans(card.id))
            .single;
        expect(
          refunded.plan.principal + refunded.plan.fixedFee,
          plan.principal + plan.fixedFee,
        );
        expect(refunded.refunds, hasLength(1));
        expect(refunded.refunded, Money.parse(twd, '10'));
        await engine.lock();
        engine = open();
        await engine.unlock(password);
        expect(
          (await engine.savedCardInstallmentPlans(card.id)).single.refunded,
          Money.parse(twd, '10'),
        );
      } finally {
        await engine.lock();
        deleteSynthetic(work, root);
      }
    },
  );
}
