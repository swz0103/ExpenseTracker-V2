import 'dart:io';

import 'package:accounts/accounts.dart';
import 'package:credit_cards/credit_cards.dart';
import 'package:expense_preview/preview_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:ledger_generation_probe/ledger_store.dart';
import 'package:storage_generation_probe/generation_store.dart';

import 'support.dart';

void main() {
  final root = Directory('.dart_tool/card-authorization-flow-tests')
    ..createSync(recursive: true);

  test('authorization, cancellation, and posting replay after lost acknowledgement', () async {
    final work = root.createTempSync('case-');
    final vault = MemoryVault();
    final failures = <String>{
      'card-authorization-committed',
      'card-cancellation-committed',
      'card-posting-committed',
    };
    PreviewEngine open() => engineAt(
      work,
      vault,
      schemaVersion: 19,
      draftCheckpoint: (point) {
        if (failures.remove(point)) {
          throw StateError('synthetic acknowledgement loss: $point');
        }
      },
    );
    var engine = open();
    try {
      await setup(engine);
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

      final authorizedOn = BusinessDate(2026, 9, 20);
      Future<CardAuthorizationFact> authorize(
        Money amount, {
        bool startNew = false,
      }) => engine.submitCardAuthorization(
        cardId: card.id,
        authorizedOn: authorizedOn,
        authorizedAmount: amount,
        startNew: startNew,
      );
      await expectLater(
        authorize(Money.parse(currency, '11')),
        throwsA(isA<StateError>()),
      );
      expect(
        (await engine.pendingCardAuthorizationIntents()).authorization,
        isTrue,
      );
      expect(
        (await engine.savedCardAuthorizations()).single.state,
        CardAuthorizationState.pending,
      );
      expect((await engine.accounts()).single.balance.minorUnits, BigInt.zero);
      await expectLater(
        authorize(Money.parse(currency, '12')),
        throwsA(isA<DraftNeedsResolution>()),
      );
      await engine.lock();
      engine = open();
      await engine.unlock(password);
      await engine.retryPendingCardAuthorizationIntent('authorization');
      final first = await authorize(Money.parse(currency, '11'));
      expect((await engine.savedCardAuthorizations()), hasLength(1));
      final second = await authorize(
        Money.parse(currency, '11'),
        startNew: true,
      );
      expect(second.charge.id, isNot(first.charge.id));
      expect((await engine.savedCardAuthorizations()), hasLength(2));

      await expectLater(
        engine.submitCardAuthorizationCancellation(second.charge.id),
        throwsA(isA<StateError>()),
      );
      expect(
        (await engine.pendingCardAuthorizationIntents()).cancellation,
        isTrue,
      );
      await engine.lock();
      engine = open();
      await engine.unlock(password);
      final cancelled = await engine.retryPendingCardAuthorizationIntent(
        'cancellation',
      ) as CardAuthorizationFact;
      expect(cancelled.state, CardAuthorizationState.cancelled);
      await engine.submitCardAuthorizationCancellation(second.charge.id);
      expect((await engine.accounts()).single.balance.minorUnits, BigInt.zero);

      final postedOn = BusinessDate(2026, 9, 22);
      Future<void> post(Money amount) => engine.submitAuthorizedCardPurchase(
        chargeId: first.charge.id,
        postedOn: postedOn,
        settledAmount: amount,
      );
      await expectLater(
        post(Money.parse(currency, '10')),
        throwsA(isA<StateError>()),
      );
      expect((await engine.pendingCardAuthorizationIntents()).posting, isTrue);
      await expectLater(
        post(Money.parse(currency, '9')),
        throwsA(isA<DraftNeedsResolution>()),
      );
      await engine.lock();
      engine = open();
      await engine.unlock(password);
      await engine.retryPendingCardAuthorizationIntent('posting');
      await post(Money.parse(currency, '10'));
      expect((await engine.accounts()).single.balance.majorText, '-10.00');
      final facts = await engine.savedCardAuthorizations();
      expect(
        facts.singleWhere((fact) => fact.charge.id == first.charge.id).state,
        CardAuthorizationState.posted,
      );
      expect(
        facts.singleWhere((fact) => fact.charge.id == second.charge.id).state,
        CardAuthorizationState.cancelled,
      );
      expect(
        (await engine.entries()).where(
          (entry) => entry.kind == PostingKind.expense,
        ),
        hasLength(1),
      );
      expect((await engine.pendingCardAuthorizationIntents()).posting, isFalse);
    } finally {
      await engine.lock();
      deleteSynthetic(work, root);
    }
  });

  test(
    'schema 18 card upgrades safely and schema 19 backup restores twice',
    () async {
      final work = root.createTempSync('upgrade-');
      final vault = MemoryVault();
      var engine = engineAt(work, vault, schemaVersion: 18);
      try {
        final recoveryKey = await setup(engine);
        final currency = Currency('TWD', 2);
        final card = Account.open(
          id: PublicId.generate(),
          workspace: engine.workspace,
          name: 'Upgraded card',
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
        await engine.lock();
        var interrupted = false;
        engine = engineAt(
          work,
          vault,
          schemaVersion: 19,
          checkpoint: (point) {
            if (!interrupted && point == '18:table:card_authorizations') {
              interrupted = true;
              throw StateError('synthetic staged interruption');
            }
          },
        );
        await expectLater(
          engine.unlock(password),
          throwsA(isA<PreviewUpgradeRequired>()),
        );
        await expectLater(
          engine.upgrade(password),
          throwsA(isA<GenerationUnavailable>()),
        );
        expect(interrupted, isTrue);
        await engine.lock();
        engine = engineAt(work, vault, schemaVersion: 18);
        await engine.unlock(password);
        expect(
          (await engine.accounts()).single.balance.minorUnits,
          BigInt.zero,
        );
        await engine.lock();
        engine = engineAt(work, vault, schemaVersion: 19);
        await engine.upgrade(password);
        final auth = await engine.submitCardAuthorization(
          cardId: card.id,
          authorizedOn: BusinessDate(2026, 9, 29),
          authorizedAmount: Money.parse(currency, '20'),
        );
        await engine.submitAuthorizedCardPurchase(
          chargeId: auth.charge.id,
          postedOn: BusinessDate(2026, 9, 30),
          settledAmount: Money.parse(currency, '19'),
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
              (await target.savedCardAuthorizations()).single.state,
              CardAuthorizationState.posted,
            );
            expect(
              (await target.accounts()).single.balance.majorText,
              '-19.00',
            );
            expect(
              (await target.entries()).where(
                (entry) => entry.kind == PostingKind.expense,
              ),
              hasLength(1),
            );
          } finally {
            await target.lock();
            deleteSynthetic(targetDir, root);
          }
        }
      } finally {
        await engine.lock();
        deleteSynthetic(work, root);
      }
    },
  );
}
