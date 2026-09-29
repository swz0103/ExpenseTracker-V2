import 'dart:convert';
import 'dart:io';

import 'package:accounts/accounts.dart';
import 'package:backup_envelope_probe/envelope.dart';
import 'package:credit_cards/credit_cards.dart';
import 'package:expense_preview/preview_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';

import 'support.dart';

void main() {
  final root = Directory('.dart_tool/card-installment-upgrade-tests')
    ..createSync(recursive: true);

  test(
    '18 to 20 retains purchase and restores plan with both credentials',
    () async {
      final work = root.createTempSync('case-');
      final vault = MemoryVault();
      var engine = engineAt(work, vault, schemaVersion: 18);
      try {
        final recoveryKey = await setup(engine);
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
        final oldBalance = (await engine.accounts()).single.balance;
        await engine.lock();

        engine = engineAt(work, vault, schemaVersion: 20);
        await expectLater(
          engine.unlock(password),
          throwsA(isA<PreviewUpgradeRequired>()),
        );
        await engine.upgrade(password);
        expect((await engine.accounts()).single.balance, oldBalance);
        final purchase = (await engine.availableInstallmentPurchases(card.id))
            .single;
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
        await engine.submitCardInstallmentPlan(plan);
        final backup = await engine.exportBackup();
        final plain = await EnvelopeCodec().openWithPassword(backup, password);
        expect(jsonDecode(utf8.decode(plain))['schema'], 20);

        for (final useRecovery in [false, true]) {
          final restoredDir = root.createTempSync('restore-');
          final restored = engineAt(
            restoredDir,
            MemoryVault(),
            schemaVersion: 20,
          );
          try {
            await setup(restored);
            await restored.importBackup(
              backup,
              useRecovery ? recoveryKey : password,
              recovery: useRecovery,
            );
            final saved = (await restored.savedCardInstallmentPlans(card.id))
                .single
                .plan;
            expect(saved.count, 3);
            expect(saved.principal, plan.principal);
            expect((await restored.accounts()).single.balance, oldBalance);
          } finally {
            await restored.lock();
            deleteSynthetic(restoredDir, root);
          }
        }
      } finally {
        await engine.lock();
        deleteSynthetic(work, root);
      }
    },
  );
}
