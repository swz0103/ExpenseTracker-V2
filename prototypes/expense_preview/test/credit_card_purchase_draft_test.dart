import 'dart:io';

import 'package:accounts/accounts.dart';
import 'package:credit_cards/credit_cards.dart';
import 'package:expense_preview/preview_engine.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  test('committed card draft reopens without a second purchase', () async {
    final root = Directory('.dart_tool/card-purchase-draft-tests')
      ..createSync(recursive: true);
    final work = root.createTempSync('case-');
    final vault = MemoryVault();
    String? stop;
    PreviewEngine open() => engineAt(
      work,
      vault,
      schemaVersion: 17,
      draftCheckpoint: (point) {
        if (point == stop) throw StateError('injected-$point');
      },
    );
    var engine = open();
    try {
      final recoveryKey = await setup(engine);
      final currency = Currency('TWD', 2);
      final card = Account.open(
        id: PublicId.generate(),
        workspace: engine.workspace,
        name: '合成測試卡',
        kind: AccountKind.creditCard,
        currency: currency,
        openedOn: BusinessDate(2026, 9, 1),
      );
      await engine.createAccount(
        card,
        Posting.opening(
          id: PublicId.generate(),
          operation: OperationKey(
            card.workspace,
            OperationId(PublicId.generate()),
          ),
          date: card.openedOn,
          account: PostingAccount(
            id: card.id,
            workspace: card.workspace,
            currency: currency,
            expectedVersion: card.version,
          ),
          amount: Money(currency, BigInt.zero),
        ),
        cardTerms: CreditCardTerms(
          workspace: card.workspace,
          cardId: card.id,
          currency: currency,
          closingDay: 28,
          dueDay: 12,
        ),
      );
      final draft = await engine.saveEntryDraft(
        EntryFields(
          income: false,
          amount: '123.45',
          date: '2026-09-29',
          accountId: card.id,
        ),
      );
      stop = 'draft-committed';
      await expectLater(engine.submitEntryDraft(), throwsStateError);
      expect(
        (await engine.accounts()).single.balance.minorUnits,
        BigInt.from(-12345),
      );
      await engine.lock();
      stop = null;
      engine = open();
      await engine.unlock(password);
      expect(await engine.entryDraft(), null);
      final purchases = (await engine.entries())
          .where((entry) => entry.kind == PostingKind.expense)
          .toList();
      expect(purchases, hasLength(1));
      expect(purchases.single.id, draft.id);
      expect(
        (await engine.accounts()).single.balance.minorUnits,
        BigInt.from(-12345),
      );
      final backup = await engine.exportBackup();
      for (final recovery in [false, true]) {
        final restoredDir = root.createTempSync('restore-');
        final restored = engineAt(
          restoredDir,
          MemoryVault(),
          schemaVersion: 17,
        );
        try {
          await setup(restored);
          await restored.importBackup(
            backup,
            recovery ? recoveryKey : password,
            recovery: recovery,
          );
          expect(
            (await restored.accounts()).single.balance.minorUnits,
            BigInt.from(-12345),
          );
          expect(
            (await restored.entries()).where(
              (entry) => entry.kind == PostingKind.expense,
            ),
            hasLength(1),
          );
        } finally {
          await restored.lock();
          deleteSynthetic(restoredDir, root);
        }
      }
    } finally {
      await engine.lock();
      deleteSynthetic(work, root);
    }
  });
}
