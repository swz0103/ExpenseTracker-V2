import 'dart:io';

import 'package:accounts/accounts.dart';
import 'package:credit_cards/credit_cards.dart';
import 'package:expense_preview/main.dart';
import 'package:expense_preview/preview_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:storage_generation_probe/generation_store.dart';

import 'support.dart';
import 'widget_test.dart' show Documents, closeEngine, settle, tap, input;

void main() {
  final root = Directory('.dart_tool/card-statement-flow-tests')
    ..createSync(recursive: true);

  test('confirmed bill and partial allocation survive reopen', () async {
    final work = root.createTempSync('case-');
    final vault = MemoryVault();
    PreviewEngine open() => engineAt(work, vault, schemaVersion: 18);
    var engine = open();
    try {
      final recoveryKey = await setup(engine);
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

      final statementId = PublicId.generate();
      final confirmOperation = OperationId(PublicId.generate());
      final cycle = CardCycle(
        startsAfter: BusinessDate(2026, 8, 29),
        closesOn: BusinessDate(2026, 9, 29),
        dueOn: BusinessDate(2026, 10, 15),
      );
      await engine.confirmCardStatement(
        statementId: statementId,
        cardId: card.id,
        revision: 1,
        cycle: cycle,
        billed: Money.parse(currency, '101'),
        operation: confirmOperation,
      );
      await engine.confirmCardStatement(
        statementId: statementId,
        cardId: card.id,
        revision: 1,
        cycle: cycle,
        billed: Money.parse(currency, '101'),
        operation: confirmOperation,
      );
      final before = (await engine.confirmedCardStatements(card.id)).single;
      expect(before.billed.majorText, '101.00');
      expect(before.localCharges.majorText, '100.00');
      expect(before.remainingDue.majorText, '101.00');
      final payment = (await engine.unallocatedCardPayments(card.id)).single;
      expect(payment.unallocated.majorText, '50.00');

      final allocateOperation = OperationId(PublicId.generate());
      Future<void> allocate() => engine.allocateCardPayment(
        paymentEventId: payment.eventId,
        statementId: statementId,
        statementRevision: 1,
        amount: Money.parse(currency, '40'),
        operation: allocateOperation,
      );
      await allocate();
      await allocate();
      expect(
        (await engine.confirmedCardStatements(card.id))
            .single
            .remainingDue
            .majorText,
        '61.00',
      );
      expect(
        (await engine.unallocatedCardPayments(card.id))
            .single
            .unallocated
            .majorText,
        '10.00',
      );
      final backup = await engine.exportBackup();
      for (final useRecovery in [false, true]) {
        final targetDir = root.createTempSync('restore-');
        final target = engineAt(targetDir, MemoryVault(), schemaVersion: 18);
        try {
          await setup(target);
          await target.importBackup(
            backup,
            useRecovery ? recoveryKey : password,
            recovery: useRecovery,
          );
          expect(
            (await target.confirmedCardStatements(card.id))
                .single
                .remainingDue
                .majorText,
            '61.00',
          );
          expect(
            (await target.unallocatedCardPayments(card.id))
                .single
                .unallocated
                .majorText,
            '10.00',
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
        (await engine.confirmedCardStatements(card.id))
            .single
            .remainingDue
            .majorText,
        '61.00',
      );
      expect(
        (await engine.unallocatedCardPayments(card.id))
            .single
            .unallocated
            .majorText,
        '10.00',
      );
    } finally {
      await engine.lock();
      deleteSynthetic(work, root);
    }
  });

  test(
    'schema 17 card entries survive interrupted schema 18 upgrade',
    () async {
      final work = root.createTempSync('upgrade-');
      final vault = MemoryVault();
      var engine = engineAt(work, vault, schemaVersion: 17);
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
                  ? Money.parse(currency, '100')
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
            amount: '12.34',
            date: '2026-09-27',
            accountId: card.id,
          ),
        );
        await engine.submitEntryDraft();
        await engine.saveEntryDraft(
          EntryFields(
            income: false,
            amount: '5',
            date: '2026-09-30',
            transfer: true,
            accountId: bank.id,
            destinationId: card.id,
          ),
        );
        await engine.submitEntryDraft();
        final before = {
          for (final row in await engine.accounts())
            row.account.id: row.balance,
        };
        await engine.lock();
        engine = engineAt(
          work,
          vault,
          schemaVersion: 18,
          checkpoint: (point) {
            if (point == '17:table:card_posted_charges') {
              throw StateError('synthetic staged failure');
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
        await engine.lock();
        engine = engineAt(work, vault, schemaVersion: 17);
        await engine.unlock(password);
        expect({
          for (final row in await engine.accounts())
            row.account.id: row.balance,
        }, before);
        await engine.lock();
        engine = engineAt(work, vault, schemaVersion: 18);
        await engine.upgrade(password);
        expect(await engine.confirmedCardStatements(card.id), isEmpty);
        expect(
          (await engine.unallocatedCardPayments(card.id)).single.unallocated,
          Money.parse(currency, '5'),
        );
        expect({
          for (final row in await engine.accounts())
            row.account.id: row.balance,
        }, before);
      } finally {
        await engine.lock();
        deleteSynthetic(work, root);
      }
    },
  );

  testWidgets('user confirms actual issuer dates from the card screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 960);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final work = root.createTempSync('widget-');
    final engine = engineAt(work, MemoryVault(), schemaVersion: 18);
    late Account card;
    try {
      await tester.runAsync(() async {
        await setup(engine);
        final currency = Currency('TWD', 2);
        card = Account.open(
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
        final bank = Account.open(
          id: PublicId.generate(),
          workspace: engine.workspace,
          name: 'Synthetic bank',
          kind: AccountKind.bank,
          currency: currency,
          openedOn: card.openedOn,
        );
        await engine.createAccount(
          bank,
          Posting.opening(
            id: PublicId.generate(),
            operation: OperationKey(
              engine.workspace,
              OperationId(PublicId.generate()),
            ),
            date: bank.openedOn,
            account: ref(bank),
            amount: Money.parse(currency, '100'),
          ),
        );
        await engine.saveEntryDraft(
          EntryFields(
            income: false,
            amount: '12.34',
            date: '2026-09-27',
            accountId: card.id,
          ),
        );
        await engine.submitEntryDraft();
        await engine.saveEntryDraft(
          EntryFields(
            income: false,
            transfer: true,
            amount: '5',
            date: '2026-09-30',
            accountId: bank.id,
            destinationId: card.id,
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
      await tap(tester, '信用卡帳單');
      final reveal = find.byIcon(Icons.visibility_off_outlined);
      if (reveal.evaluate().isNotEmpty) {
        await tester.tap(reveal);
        await settle(tester);
      }
      for (final (key, value) in [
        ('statement-start', '2026-08-29'),
        ('statement-close', '2026-09-29'),
        ('statement-due', '2026-10-15'),
        ('statement-billed', '13'),
      ]) {
        final field = find.byKey(ValueKey(key));
        await tester.ensureVisible(field);
        await tester.enterText(field, value);
      }
      final confirm = find.byKey(const ValueKey('confirm-statement'));
      await tester.ensureVisible(confirm);
      await tester.tap(confirm);
      await settle(tester);
      final rows = (await tester.runAsync(
        () => engine.confirmedCardStatements(card.id),
      ))!;
      expect(rows, hasLength(1));
      expect(rows.single.cycle.closesOn, BusinessDate(2026, 9, 29));
      expect(rows.single.remainingDue.majorText, '13.00');
      expect(rows.single.localCharges.majorText, '12.34');
      expect(find.textContaining('金額不符請核對'), findsOneWidget);
      final revise = find.byKey(ValueKey('revise-statement-${rows.single.id}'));
      await tester.ensureVisible(revise);
      await tester.tap(revise);
      await tester.pump();
      expect(find.text('確認並保存帳單修訂'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('statement-due')),
        '2026-10-16',
      );
      await tester.enterText(
        find.byKey(const ValueKey('statement-billed')),
        '14',
      );
      await tester.tap(find.byKey(const ValueKey('confirm-statement')));
      await settle(tester);
      final revised = (await tester.runAsync(
        () => engine.confirmedCardStatements(card.id),
      ))!.single;
      expect(revised.id, rows.single.id);
      expect(revised.revision, 2);
      expect(revised.cycle.dueOn, BusinessDate(2026, 10, 16));
      expect(revised.billed.majorText, '14.00');
      final statementPicker = find.byKey(
        const ValueKey('allocation-statement'),
      );
      await tester.ensureVisible(statementPicker);
      await tester.tap(statementPicker);
      await settle(tester);
      await tester.tap(find.textContaining('2026-09-29').last);
      await settle(tester);
      final paymentPicker = find.byKey(const ValueKey('allocation-payment'));
      await tester.ensureVisible(paymentPicker);
      await tester.tap(paymentPicker);
      await settle(tester);
      await tester.tap(find.textContaining('2026-09-30').last);
      await settle(tester);
      final amount = find.byKey(const ValueKey('allocation-amount'));
      await tester.ensureVisible(amount);
      await tester.enterText(amount, '2');
      final allocate = find.byKey(const ValueKey('allocate-payment'));
      await tester.ensureVisible(allocate);
      await tester.tap(allocate);
      await settle(tester);
      final allocated = (await tester.runAsync(
        () => engine.confirmedCardStatements(card.id),
      ))!;
      expect(allocated.single.remainingDue.majorText, '12.00');
      expect(find.text('已分配，不可修訂'), findsOneWidget);
      final payments = (await tester.runAsync(
        () => engine.unallocatedCardPayments(card.id),
      ))!;
      expect(payments.single.unallocated.majorText, '3.00');
    } finally {
      await closeEngine(tester, engine);
      await tester.pumpWidget(const SizedBox());
      deleteSynthetic(work, root);
    }
  });
}
