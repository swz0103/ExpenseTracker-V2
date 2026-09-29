import 'dart:io';

import 'package:accounts/accounts.dart';
import 'package:credit_cards/credit_cards.dart';
import 'package:expense_preview/preview_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';

import 'support.dart';

void main() {
  final root = Directory('.dart_tool/card-statement-intent-retry-tests')
    ..createSync(recursive: true);

  test(
    'ambiguous statement and allocation commits replay after process exit',
    () async {
      final work = root.createTempSync('case-');
      final vault = MemoryVault();
      var failConfirmation = true;
      var failAllocation = true;
      PreviewEngine open() => engineAt(
        work,
        vault,
        schemaVersion: 18,
        draftCheckpoint: (point) {
          if (point == 'card-confirmation-committed' && failConfirmation) {
            failConfirmation = false;
            throw StateError('synthetic confirmation acknowledgement loss');
          }
          if (point == 'card-allocation-committed' && failAllocation) {
            failAllocation = false;
            throw StateError('synthetic allocation acknowledgement loss');
          }
        },
      );
      var engine = open();
      try {
        await setup(engine);
        final currency = Currency('TWD', 2);
        final bank = Account.open(
          id: PublicId.generate(),
          workspace: engine.workspace,
          name: 'Synthetic bank',
          kind: AccountKind.bank,
          currency: currency,
          openedOn: BusinessDate(2026, 9, 1),
        );
        final card = Account.open(
          id: PublicId.generate(),
          workspace: engine.workspace,
          name: 'Synthetic card',
          kind: AccountKind.creditCard,
          currency: currency,
          openedOn: BusinessDate(2026, 9, 1),
        );
        for (final account in [bank, card]) {
          await engine.createAccount(
            account,
            Posting.opening(
              id: PublicId.generate(),
              operation: OperationKey(
                engine.workspace,
                OperationId(PublicId.generate()),
              ),
              date: account.openedOn,
              account: ref(account),
              amount: account.id == bank.id
                  ? Money.parse(currency, '500')
                  : Money(currency, BigInt.zero),
            ),
            cardTerms: account.id == card.id
                ? CreditCardTerms(
                    workspace: engine.workspace,
                    cardId: card.id,
                    currency: currency,
                    closingDay: 28,
                    dueDay: 15,
                  )
                : null,
          );
        }
        await engine.saveEntryDraft(
          EntryFields(
            income: false,
            amount: '100',
            date: '2026-09-27',
            accountId: card.id,
          ),
        );
        await engine.submitEntryDraft();
        await engine.saveEntryDraft(
          EntryFields(
            income: false,
            amount: '50',
            date: '2026-09-30',
            transfer: true,
            accountId: bank.id,
            destinationId: card.id,
          ),
        );
        await engine.submitEntryDraft();

        final cycle = CardCycle(
          startsAfter: BusinessDate(2026, 8, 29),
          closesOn: BusinessDate(2026, 9, 29),
          dueOn: BusinessDate(2026, 10, 15),
        );
        Future<void> confirm(Money amount) =>
            engine.submitCardStatementConfirmation(
              cardId: card.id,
              cycle: cycle,
              billed: amount,
            );
        await expectLater(
          confirm(Money.parse(currency, '101')),
          throwsA(isA<StateError>()),
        );
        expect(
          (await engine.pendingCardStatementIntents()).confirmation,
          isTrue,
        );
        await expectLater(
          confirm(Money.parse(currency, '102')),
          throwsA(isA<DraftNeedsResolution>()),
        );
        await engine.lock();
        engine = open();
        await engine.unlock(password);
        expect((await engine.confirmedCardStatements(card.id)), hasLength(1));
        await engine.retryPendingCardStatementIntent('confirmation');
        await confirm(Money.parse(currency, '101'));
        final statement = (await engine.confirmedCardStatements(card.id))
            .single;
        expect(statement.billed.majorText, '101.00');
        expect(
          (await engine.pendingCardStatementIntents()).confirmation,
          isFalse,
        );

        final payment = (await engine.unallocatedCardPayments(card.id)).single;
        Future<void> allocate(Money amount) =>
            engine.submitCardPaymentAllocation(
              paymentEventId: payment.eventId,
              statementId: statement.id,
              statementRevision: statement.revision,
              cardId: card.id,
              amount: amount,
            );
        await expectLater(
          allocate(Money.parse(currency, '10')),
          throwsA(isA<StateError>()),
        );
        expect((await engine.pendingCardStatementIntents()).allocation, isTrue);
        await expectLater(
          allocate(Money.parse(currency, '5')),
          throwsA(isA<DraftNeedsResolution>()),
        );
        await engine.lock();
        engine = open();
        await engine.unlock(password);
        await engine.retryPendingCardStatementIntent('allocation');
        expect(
          (await engine.confirmedCardStatements(card.id)).single.paid.majorText,
          '10.00',
        );
        await allocate(Money.parse(currency, '10'));
        expect(
          (await engine.confirmedCardStatements(card.id)).single.paid.majorText,
          '10.00',
        );
        await allocate(Money.parse(currency, '5'));
        expect(
          (await engine.confirmedCardStatements(card.id)).single.paid.majorText,
          '15.00',
        );
        expect(
          (await engine.unallocatedCardPayments(card.id))
              .single
              .unallocated
              .majorText,
          '35.00',
        );
      } finally {
        await engine.lock();
        deleteSynthetic(work, root);
      }
    },
  );
}
