import 'dart:convert';
import 'dart:io';

import 'package:accounts/accounts.dart';
import 'package:credit_cards/credit_cards.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:ledger_generation_probe/ledger_store.dart';
import 'package:storage_generation_probe/fixture_catalog_protection.dart';
import 'package:storage_generation_probe/fixture_key_slots.dart';
import 'package:test/test.dart';

void main() {
  final root = Directory('.dart_tool/card-statement-session-tests')
    ..createSync(recursive: true);
  final currency = Currency('TWD', 2);
  late Directory work;
  late WorkspaceId workspace;
  late LedgerStore store;
  late Account card, bank;

  OperationId op() => OperationId(PublicId.generate());
  OperationKey operation() => OperationKey(workspace, op());
  PostingAccount ref(Account account) => PostingAccount(
    id: account.id,
    workspace: workspace,
    currency: account.currency,
    expectedVersion: account.version,
  );
  final cycle = CardCycle(
    startsAfter: BusinessDate(2026, 9, 28),
    closesOn: BusinessDate(2026, 10, 28),
    dueOn: BusinessDate(2026, 11, 15),
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
      cardStatementsAware: true,
    );
    await store.initialize(op());
    card = Account.open(
      id: PublicId.generate(),
      workspace: workspace,
      name: 'Synthetic card',
      kind: AccountKind.creditCard,
      currency: currency,
      openedOn: BusinessDate(2026, 1, 1),
    );
    bank = Account.open(
      id: PublicId.generate(),
      workspace: workspace,
      name: 'Synthetic bank',
      kind: AccountKind.bank,
      currency: currency,
      openedOn: BusinessDate(2026, 1, 1),
    );
    await store.withSession((session) async {
      await session.createAccount(
        card,
        Posting.opening(
          id: PublicId.generate(),
          operation: operation(),
          date: card.openedOn,
          account: ref(card),
          amount: Money(currency, BigInt.zero),
        ),
        cardTerms: CreditCardTerms(
          workspace: workspace,
          cardId: card.id,
          currency: currency,
          closingDay: 28,
          dueDay: 15,
        ),
      );
      await session.createAccount(
        bank,
        Posting.opening(
          id: PublicId.generate(),
          operation: operation(),
          date: bank.openedOn,
          account: ref(bank),
          amount: Money.parse(currency, '100'),
        ),
      );
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
    'new card facts, actual cycle and partial payment remain authoritative',
    () async {
      final charge = Posting.expense(
        id: PublicId.generate(),
        operation: operation(),
        date: BusinessDate(2026, 9, 29),
        account: ref(card),
        amount: Money.parse(currency, '12.34'),
      );
      final payment = Posting.transfer(
        id: PublicId.generate(),
        operation: operation(),
        date: BusinessDate(2026, 9, 30),
        source: ref(bank),
        destination: ref(card),
        principal: Money.parse(currency, '5'),
      );
      final statementId = PublicId.generate();
      final confirmOp = op();
      final allocateOp = op();
      await store.withSession((session) async {
        await session.postCardPurchase(charge);
        await session.postCardPayment(payment);
        await session.confirmCardStatement(
          workspace: workspace,
          statementId: statementId,
          cardId: card.id,
          revision: 1,
          cycle: cycle,
          billed: Money.parse(currency, '12.34'),
          operation: confirmOp,
        );
        await session.confirmCardStatement(
          workspace: workspace,
          statementId: statementId,
          cardId: card.id,
          revision: 1,
          cycle: cycle,
          billed: Money.parse(currency, '12.34'),
          operation: confirmOp,
        );
        var statement = (await session.confirmedCardStatements(
          workspace: workspace,
          cardId: card.id,
        )).single;
        expect(statement.billed, Money.parse(currency, '12.34'));
        expect(statement.paid, Money(currency, BigInt.zero));
        expect(statement.remainingDue, Money.parse(currency, '12.34'));
        expect(
          (await session.unallocatedCardPayments(
            workspace: workspace,
            cardId: card.id,
          )).single.unallocated,
          Money.parse(currency, '5'),
        );
        await session.allocateCardPayment(
          workspace: workspace,
          paymentEventId: payment.id,
          statementId: statementId,
          statementRevision: 1,
          amount: Money.parse(currency, '2'),
          operation: allocateOp,
        );
        await session.allocateCardPayment(
          workspace: workspace,
          paymentEventId: payment.id,
          statementId: statementId,
          statementRevision: 1,
          amount: Money.parse(currency, '2'),
          operation: allocateOp,
        );
        statement = (await session.confirmedCardStatements(
          workspace: workspace,
          cardId: card.id,
        )).single;
        expect(statement.paid, Money.parse(currency, '2'));
        expect(statement.remainingDue, Money.parse(currency, '10.34'));
        expect(
          (await session.unallocatedCardPayments(
            workspace: workspace,
            cardId: card.id,
          )).single.unallocated,
          Money.parse(currency, '3'),
        );
        final before = await session.snapshot();
        await expectLater(
          session.allocateCardPayment(
            workspace: workspace,
            paymentEventId: payment.id,
            statementId: statementId,
            statementRevision: 1,
            amount: Money.parse(currency, '2.01'),
            operation: allocateOp,
          ),
          throwsFormatException,
        );
        await expectLater(
          session.allocateCardPayment(
            workspace: workspace,
            paymentEventId: payment.id,
            statementId: PublicId.generate(),
            statementRevision: 1,
            amount: Money.parse(currency, '1'),
            operation: op(),
          ),
          throwsFormatException,
        );
        expect(await session.snapshot(), before);
      });
      final snapshot = jsonDecode(utf8.decode(await store.snapshot())) as Map;
      final tables = snapshot['tables'] as Map;
      expect(tables['card_posted_charges'], hasLength(1));
      expect(tables['card_payments'], hasLength(1));
      expect(tables['card_statements'], hasLength(1));
      expect(tables['card_payment_allocations'], hasLength(1));
    },
  );

  test('card opening with nonzero balance is refused in schema 18', () async {
    final another = Account.open(
      id: PublicId.generate(),
      workspace: workspace,
      name: 'Another card',
      kind: AccountKind.creditCard,
      currency: currency,
      openedOn: BusinessDate(2026, 1, 1),
    );
    await store.withSession((session) async {
      final before = await session.snapshot();
      await expectLater(
        session.createAccount(
          another,
          Posting.opening(
            id: PublicId.generate(),
            operation: operation(),
            date: another.openedOn,
            account: ref(another),
            amount: Money.parse(currency, '-5'),
          ),
          cardTerms: CreditCardTerms(
            workspace: workspace,
            cardId: another.id,
            currency: currency,
            closingDay: 28,
            dueDay: 15,
          ),
        ),
        throwsA(isA<CreditCardException>()),
      );
      expect(await session.snapshot(), before);
    });
  });
}
