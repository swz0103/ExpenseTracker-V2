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
  test('committed payment draft reopens without a second bank debit', () async {
    final root = Directory('.dart_tool/card-payment-replay-tests')
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
      await setup(engine);
      final currency = Currency('TWD', 2);
      final bank = Account.open(
        id: PublicId.generate(),
        workspace: engine.workspace,
        name: '繳款銀行',
        kind: AccountKind.bank,
        currency: currency,
        openedOn: BusinessDate(2026, 9, 1),
      );
      final card = Account.open(
        id: PublicId.generate(),
        workspace: engine.workspace,
        name: '繳款卡片',
        kind: AccountKind.creditCard,
        currency: currency,
        openedOn: BusinessDate(2026, 9, 1),
      );
      for (final a in [bank, card]) {
        await engine.createAccount(
          a,
          Posting.opening(
            id: PublicId.generate(),
            operation: OperationKey(
              a.workspace,
              OperationId(PublicId.generate()),
            ),
            date: a.openedOn,
            account: PostingAccount(
              id: a.id,
              workspace: a.workspace,
              currency: currency,
              expectedVersion: a.version,
            ),
            amount: a.id == bank.id
                ? Money.parse(currency, '500')
                : Money(currency, BigInt.zero),
          ),
          cardTerms: a.id == card.id
              ? CreditCardTerms(
                  workspace: card.workspace,
                  cardId: card.id,
                  currency: currency,
                  closingDay: 28,
                  dueDay: 12,
                )
              : null,
        );
      }
      await engine.saveEntryDraft(
        EntryFields(
          income: false,
          amount: '100',
          date: '2026-09-29',
          accountId: card.id,
        ),
      );
      await engine.submitEntryDraft();
      final payment = await engine.saveEntryDraft(
        EntryFields(
          income: false,
          amount: '100',
          date: '2026-09-29',
          transfer: true,
          accountId: bank.id,
          destinationId: card.id,
        ),
      );
      stop = 'draft-committed';
      await expectLater(engine.submitEntryDraft(), throwsStateError);
      await engine.lock();
      stop = null;
      engine = open();
      await engine.unlock(password);
      expect(await engine.entryDraft(), null);
      final balances = await engine.accounts();
      expect(
        balances.singleWhere((a) => a.account.id == bank.id).balance.majorText,
        '400.00',
      );
      expect(
        balances.singleWhere((a) => a.account.id == card.id).balance.majorText,
        '0.00',
      );
      expect(
        (await engine.entries()).where((e) => e.id == payment.id),
        hasLength(1),
      );
    } finally {
      await engine.lock();
      deleteSynthetic(work, root);
    }
  });

  testWidgets('card payment uses an eligible bank and is never new spend', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 960);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final root = Directory('.dart_tool/card-payment-widget-tests')
      ..createSync(recursive: true);
    final work = root.createTempSync('case-');
    final engine = engineAt(work, MemoryVault(), schemaVersion: 17);
    late String recoveryKey;
    try {
      await tester.runAsync(() async {
        recoveryKey = await setup(engine);
        final usd = Currency('USD', 2);
        final twd = Currency('TWD', 2);
        final firstBank = Account.open(
          id: PublicId.generate(),
          workspace: engine.workspace,
          name: '美元銀行',
          kind: AccountKind.bank,
          currency: usd,
          openedOn: BusinessDate(2026, 9, 1),
        );
        final payingBank = Account.open(
          id: PublicId.generate(),
          workspace: engine.workspace,
          name: '台幣銀行',
          kind: AccountKind.bank,
          currency: twd,
          openedOn: BusinessDate(2026, 9, 1),
        );
        final card = Account.open(
          id: PublicId.generate(),
          workspace: engine.workspace,
          name: '台幣信用卡',
          kind: AccountKind.creditCard,
          currency: twd,
          openedOn: BusinessDate(2026, 9, 1),
        );
        for (final a in [firstBank, payingBank, card]) {
          await engine.createAccount(
            a,
            Posting.opening(
              id: PublicId.generate(),
              operation: OperationKey(
                a.workspace,
                OperationId(PublicId.generate()),
              ),
              date: a.openedOn,
              account: PostingAccount(
                id: a.id,
                workspace: a.workspace,
                currency: a.currency,
                expectedVersion: a.version,
              ),
              amount: a.id == card.id
                  ? Money(twd, BigInt.zero)
                  : Money.parse(a.currency, '500'),
            ),
            cardTerms: a.id == card.id
                ? CreditCardTerms(
                    workspace: card.workspace,
                    cardId: card.id,
                    currency: twd,
                    closingDay: 28,
                    dueDay: 12,
                  )
                : null,
          );
        }
        await engine.saveEntryDraft(
          EntryFields(
            income: false,
            amount: '100',
            date: '2026-09-29',
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
      await input(tester, '密碼', password);
      await tap(tester, '解鎖');
      await tap(tester, '信用卡繳款');
      expect(find.text('台幣銀行 · TWD'), findsOneWidget);
      expect(find.text('美元銀行 · USD'), findsNothing);
      await input(tester, '繳款金額', '40');
      await tap(tester, '確認信用卡繳款');
      final balances = (await tester.runAsync(() => engine.accounts()))!;
      expect(
        balances.singleWhere((a) => a.account.name == '台幣銀行').balance.majorText,
        '460.00',
      );
      expect(
        balances
            .singleWhere((a) => a.account.name == '台幣信用卡')
            .balance
            .majorText,
        '-60.00',
      );
      final entries = (await tester.runAsync(() => engine.entries()))!;
      expect(entries.where((e) => e.kind == PostingKind.expense), hasLength(1));
      expect(
        entries.where((e) => e.kind == PostingKind.transfer),
        hasLength(1),
      );
      final backup = (await tester.runAsync(engine.exportBackup))!;
      for (final recovery in [false, true]) {
        final restoredDir = root.createTempSync('restore-');
        final restored = engineAt(
          restoredDir,
          MemoryVault(),
          schemaVersion: 17,
        );
        try {
          await tester.runAsync(() async {
            await setup(restored);
            await restored.importBackup(
              backup,
              recovery ? recoveryKey : password,
              recovery: recovery,
            );
          });
          final rows = (await tester.runAsync(restored.accounts))!;
          expect(
            rows.singleWhere((a) => a.account.name == '台幣銀行').balance.majorText,
            '460.00',
          );
          expect(
            rows
                .singleWhere((a) => a.account.name == '台幣信用卡')
                .balance
                .majorText,
            '-60.00',
          );
        } finally {
          await tester.runAsync(restored.lock);
          deleteSynthetic(restoredDir, root);
        }
      }
    } finally {
      await closeEngine(tester, engine);
      await tester.pumpWidget(const SizedBox());
      deleteSynthetic(work, root);
    }
  });
}
