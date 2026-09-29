import 'dart:io';

import 'package:accounts/accounts.dart';
import 'package:credit_cards/credit_cards.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:ledger_generation_probe/ledger_store.dart';
import 'package:modular_persistence_probe/operations.dart';
import 'package:reports/reports.dart';
import 'package:storage_generation_probe/fixture_catalog_protection.dart';
import 'package:storage_generation_probe/fixture_key_slots.dart';
import 'package:test/test.dart';

void main() {
  final root = Directory('.dart_tool/card-purchase-session-tests')
    ..createSync(recursive: true);
  final twd = Currency('TWD', 2);
  late Directory work;
  late LedgerStore store;
  late WorkspaceId workspace;
  late Account card, cash, bank;

  OperationId operationId() => OperationId(PublicId.generate());
  OperationKey operation() => OperationKey(workspace, operationId());
  PostingAccount ref(Account account) => PostingAccount(
    id: account.id,
    workspace: workspace,
    currency: account.currency,
    expectedVersion: account.version,
  );
  Posting opening(Account account, String amount) => Posting.opening(
    id: PublicId.generate(),
    operation: operation(),
    date: account.openedOn,
    account: ref(account),
    amount: Money.parse(account.currency, amount),
  );
  Posting purchase({
    Account? account,
    String amount = '12.34',
    OperationKey? key,
    BusinessDate? date,
    PostingAccount? participant,
  }) => Posting.expense(
    id: PublicId.generate(),
    operation: key ?? operation(),
    date: date ?? BusinessDate(2026, 9, 29),
    account: participant ?? ref(account ?? card),
    amount: Money.parse(
      participant?.currency ?? account?.currency ?? twd,
      amount,
    ),
  );
  Posting payment({
    Account? source,
    Account? target,
    PostingAccount? destination,
    OperationKey? key,
    String amount = '5',
    Money? received,
    Money? fee,
  }) => Posting.transfer(
    id: PublicId.generate(),
    operation: key ?? operation(),
    date: BusinessDate(2026, 9, 30),
    source: ref(source ?? bank),
    destination: destination ?? ref(target ?? card),
    principal: Money.parse((source ?? bank).currency, amount),
    received: received,
    fee: fee,
  );
  CreditCardTerms terms(int version) => CreditCardTerms(
    workspace: workspace,
    cardId: card.id,
    currency: twd,
    closingDay: 28,
    dueDay: 15,
    version: version,
  );

  setUp(() async {
    work = root.createTempSync('case-');
    workspace = WorkspaceId(PublicId.generate());
    final keys = FixtureKeySlots(Directory('${work.path}/keys'));
    store = LedgerStore(
      Directory('${work.path}/store'),
      keys,
      catalogProtection: fixtureCatalogProtection(keys),
      correctionsAware: true,
      tombstonesAware: true,
      budgetsAware: true,
      recurringAware: true,
      creditCardsAware: true,
    );
    await store.initialize(operationId());
    card = Account.open(
      id: PublicId.generate(),
      workspace: workspace,
      name: 'Synthetic card',
      kind: AccountKind.creditCard,
      currency: twd,
      openedOn: BusinessDate(2026, 1, 1),
    );
    cash = Account.open(
      id: PublicId.generate(),
      workspace: workspace,
      name: 'Synthetic cash',
      kind: AccountKind.cash,
      currency: twd,
      openedOn: BusinessDate(2026, 1, 1),
    );
    bank = Account.open(
      id: PublicId.generate(),
      workspace: workspace,
      name: 'Synthetic bank',
      kind: AccountKind.bank,
      currency: twd,
      openedOn: BusinessDate(2026, 1, 1),
    );
    await store.withSession((session) async {
      await session.createAccount(
        card,
        opening(card, '0'),
        cardTerms: terms(1),
      );
      await session.createAccount(cash, opening(cash, '100'));
      await session.createAccount(bank, opening(bank, '100'));
    });
  });
  tearDown(() {
    final base = root.resolveSymbolicLinksSync();
    final target = work.resolveSymbolicLinksSync();
    if (!target.startsWith('$base${Platform.pathSeparator}')) {
      throw StateError('Unsafe synthetic cleanup');
    }
    work.deleteSync(recursive: true);
  });

  test(
    'posted purchase is one expense and one negative card balance',
    () async {
      await store.withSession((session) async {
        final charge = purchase();
        final receipts = await Future.wait(
          List.generate(5, (_) => session.postCardPurchase(charge)),
        );
        expect(receipts.where((r) => !r.replayed), hasLength(1));
        expect(receipts.map((r) => r.id).toSet(), {charge.id});
        await expectLater(
          session.postCardPurchase(
            purchase(key: charge.operation, amount: '1'),
          ),
          throwsA(isA<OperationConflict>()),
        );
        final balances = {
          for (final row in await session.accounts(workspace))
            row.account.id: row.balance,
        };
        expect(balances[card.id], Money.parse(twd, '-12.34'));
        expect(balances[cash.id], Money.parse(twd, '100'));
        final entry = (await session.entry(workspace, charge.id))!;
        expect(entry.kind, PostingKind.expense);
        expect(entry.accountId, card.id);
        expect(entry.amount, Money.parse(twd, '-12.34'));
        final report = await session.monthlyReport(
          workspace,
          ReportMonth(2026, 9),
        );
        expect(report.currencies.single.expense, Money.parse(twd, '12.34'));
        expect(report.accounts.single.accountId, card.id);
      });
    },
  );

  test(
    'disabled card rejects new purchase but committed operation replays',
    () async {
      await store.withSession((session) async {
        final charge = purchase();
        await session.postCardPurchase(charge);
        await session.reviseCreditCard(
          terms(2),
          operationId(),
          DateTime.utc(2026, 9, 29),
          disabled: true,
        );
        final before = await session.snapshot();
        expect((await session.postCardPurchase(charge)).replayed, isTrue);
        await expectLater(
          session.postCardPurchase(purchase()),
          throwsA(isA<FormatException>()),
        );
        expect(await session.snapshot(), before);
      });
    },
  );

  test(
    'invalid account, currency and date leave the ledger unchanged',
    () async {
      await store.withSession((session) async {
        final before = await session.snapshot();
        await expectLater(
          session.postCardPurchase(purchase(account: cash)),
          throwsA(isA<CreditCardException>()),
        );
        await expectLater(
          session.postCardPurchase(
            purchase(
              participant: PostingAccount(
                id: card.id,
                workspace: workspace,
                currency: Currency('USD', 2),
                expectedVersion: card.version,
              ),
            ),
          ),
          throwsA(isA<CreditCardException>()),
        );
        await expectLater(
          session.postCardPurchase(purchase(date: BusinessDate(2025, 12, 31))),
          throwsA(isA<AccountException>()),
        );
        expect(await session.snapshot(), before);
      });
    },
  );

  test('ordinary posting cannot bypass the card workflow', () async {
    await store.withSession((session) async {
      final before = await session.snapshot();
      await expectLater(
        session.post(purchase()),
        throwsA(isA<UnsupportedError>()),
      );
      await expectLater(
        session.post(
          Posting.income(
            id: PublicId.generate(),
            operation: operation(),
            date: BusinessDate(2026, 9, 29),
            account: ref(card),
            amount: Money.parse(twd, '1'),
          ),
        ),
        throwsA(isA<UnsupportedError>()),
      );
      await expectLater(
        session.post(
          Posting.transfer(
            id: PublicId.generate(),
            operation: operation(),
            date: BusinessDate(2026, 9, 29),
            source: ref(cash),
            destination: ref(card),
            principal: Money.parse(twd, '1'),
          ),
        ),
        throwsA(isA<UnsupportedError>()),
      );
      expect(await session.snapshot(), before);
      expect((await session.postCardPurchase(purchase())).replayed, isFalse);
    });
  });

  test('generic correction cannot rewrite a card purchase', () async {
    await store.withSession((session) async {
      final charge = purchase();
      await session.postCardPurchase(charge);
      final before = await session.snapshot();
      await expectLater(
        session.correct(
          PostingCorrection(
            original: charge,
            replacement: purchase(),
            reversalId: PublicId.generate(),
            reversalOperation: operation(),
          ),
        ),
        throwsA(isA<UnsupportedError>()),
      );
      expect(await session.snapshot(), before);
    });
  });

  test('generic refund and reversal cannot change a card purchase', () async {
    await store.withSession((session) async {
      final charge = purchase();
      await session.postCardPurchase(charge);
      final before = await session.snapshot();
      await expectLater(
        session.post(
          Posting.refund(
            id: PublicId.generate(),
            operation: operation(),
            date: BusinessDate(2026, 9, 30),
            account: ref(card),
            originalId: charge.id,
            amount: Money.parse(twd, '1'),
          ),
        ),
        throwsA(isA<UnsupportedError>()),
      );
      await expectLater(
        session.post(
          Posting.reversal(
            id: PublicId.generate(),
            operation: operation(),
            date: BusinessDate(2026, 9, 30),
            original: charge,
          ),
        ),
        throwsA(isA<UnsupportedError>()),
      );
      expect(await session.snapshot(), before);
      expect(
        (await session.entry(workspace, charge.id))!.amount,
        Money.parse(twd, '-12.34'),
      );
    });
  });

  test('generic tombstone cannot remove a posted card purchase', () async {
    await store.withSession((session) async {
      final charge = purchase();
      await session.postCardPurchase(charge);
      final before = await session.snapshot();
      final balancesBefore = {
        for (final row in await session.accounts(workspace))
          row.account.id: row.balance,
      };
      await expectLater(
        session.tombstone(
          PostingTombstone(
            original: charge,
            operation: operation(),
            reason: 'synthetic correction',
          ),
        ),
        throwsA(isA<UnsupportedError>()),
      );
      expect(await session.snapshot(), before);
      expect({
        for (final row in await session.accounts(workspace))
          row.account.id: row.balance,
      }, balancesBefore);
      expect(
        (await session.entry(workspace, charge.id))!.tombstoneReason,
        isNull,
      );
    });
  });

  test(
    'bank payment lowers liability without another expense and replays',
    () async {
      late Posting transfer;
      await store.withSession((session) async {
        await session.postCardPurchase(purchase());
        transfer = payment();
        final receipts = await Future.wait(
          List.generate(5, (_) => session.postCardPayment(transfer)),
        );
        expect(receipts.where((receipt) => !receipt.replayed), hasLength(1));
        expect(receipts.map((receipt) => receipt.id).toSet(), {transfer.id});
        await expectLater(
          session.postCardPayment(
            payment(key: transfer.operation, amount: '4'),
          ),
          throwsA(isA<OperationConflict>()),
        );
        final balances = {
          for (final row in await session.accounts(workspace))
            row.account.id: row.balance,
        };
        expect(balances[bank.id], Money.parse(twd, '95'));
        expect(balances[card.id], Money.parse(twd, '-7.34'));
        expect(balances[cash.id], Money.parse(twd, '100'));
        final entry = (await session.entry(workspace, transfer.id))!;
        expect(entry.kind, PostingKind.transfer);
        expect(entry.accountId, bank.id);
        expect(entry.destinationId, card.id);
        expect(entry.fee, Money(twd, BigInt.zero));
        final report = await session.monthlyReport(
          workspace,
          ReportMonth(2026, 9),
        );
        expect(report.currencies.single.expense, Money.parse(twd, '12.34'));
      });
      final before = await store.snapshot();
      await store.withSession((session) async {
        expect((await session.postCardPayment(transfer)).replayed, isTrue);
        expect(await session.snapshot(), before);
      });
    },
  );

  test(
    'payment rejects wrong owners, currency, fee and overpayment atomically',
    () async {
      await store.withSession((session) async {
        final empty = await session.snapshot();
        await expectLater(
          session.postCardPayment(payment()),
          throwsA(isA<CreditCardException>()),
        );
        expect(await session.snapshot(), empty);
        await session.postCardPurchase(purchase());
        final before = await session.snapshot();
        await expectLater(
          session.postCardPayment(payment(source: cash)),
          throwsA(isA<CreditCardException>()),
        );
        await expectLater(
          session.postCardPayment(payment(target: cash)),
          throwsA(isA<CreditCardException>()),
        );
        await expectLater(
          session.postCardPayment(
            payment(
              destination: PostingAccount(
                id: card.id,
                workspace: workspace,
                currency: Currency('USD', 2),
                expectedVersion: card.version,
              ),
              received: Money.parse(Currency('USD', 2), '5'),
            ),
          ),
          throwsA(isA<CreditCardException>()),
        );
        await expectLater(
          session.postCardPayment(payment(fee: Money.parse(twd, '1'))),
          throwsA(isA<ArgumentError>()),
        );
        await expectLater(
          session.postCardPayment(payment(amount: '13')),
          throwsA(isA<CreditCardException>()),
        );
        expect(await session.snapshot(), before);
      });
    },
  );

  test('disabled card can still pay its outstanding liability', () async {
    await store.withSession((session) async {
      await session.postCardPurchase(purchase());
      await session.reviseCreditCard(
        terms(2),
        operationId(),
        DateTime.utc(2026, 9, 30),
        disabled: true,
      );
      expect((await session.postCardPayment(payment())).replayed, isFalse);
      final balances = {
        for (final row in await session.accounts(workspace))
          row.account.id: row.balance,
      };
      expect(balances[card.id], Money.parse(twd, '-7.34'));
    });
  });

  test('full payment replays after liability reaches zero', () async {
    await store.withSession((session) async {
      await session.postCardPurchase(purchase());
      final full = payment(amount: '12.34');
      expect((await session.postCardPayment(full)).replayed, isFalse);
      final before = await session.snapshot();
      expect((await session.postCardPayment(full)).replayed, isTrue);
      expect(await session.snapshot(), before);
      final balances = {
        for (final row in await session.accounts(workspace))
          row.account.id: row.balance,
      };
      expect(balances[card.id], Money(twd, BigInt.zero));
      expect(balances[bank.id], Money.parse(twd, '87.66'));
      await expectLater(
        session.postCardPayment(payment(amount: '1')),
        throwsA(isA<CreditCardException>()),
      );
      expect(await session.snapshot(), before);
    });
  });
}
