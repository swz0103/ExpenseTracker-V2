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
  final root = Directory('.dart_tool/card-authorization-session-tests')
    ..createSync(recursive: true);
  final twd = Currency('TWD', 2);
  final usd = Currency('USD', 2);
  late Directory work;
  late WorkspaceId workspace;
  late LedgerStore store;
  late Account card;

  OperationId op() => OperationId(PublicId.generate());
  OperationKey operation() => OperationKey(workspace, op());
  PostingAccount ref() => PostingAccount(
    id: card.id,
    workspace: workspace,
    currency: card.currency,
    expectedVersion: card.version,
  );
  CardCharge pending() => CardCharge.pending(
    id: PublicId.generate(),
    workspace: workspace,
    cardId: card.id,
    kind: CardChargeKind.purchase,
    authorizedOn: BusinessDate(2026, 9, 29),
    authorizedAmount: Money.parse(usd, '10'),
  );
  Posting purchase(Money amount, {OperationKey? key, PublicId? id}) =>
      Posting.expense(
        id: id ?? PublicId.generate(),
        operation: key ?? operation(),
        date: BusinessDate(2026, 9, 30),
        account: ref(),
        amount: amount,
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
      cardAuthorizationsAware: true,
    );
    await store.initialize(op());
    card = Account.open(
      id: PublicId.generate(),
      workspace: workspace,
      name: 'Synthetic card',
      kind: AccountKind.creditCard,
      currency: twd,
      openedOn: BusinessDate(2026, 1, 1),
    );
    await store.withSession(
      (session) => session.createAccount(
        card,
        Posting.opening(
          id: PublicId.generate(),
          operation: operation(),
          date: card.openedOn,
          account: ref(),
          amount: Money(twd, BigInt.zero),
        ),
        cardTerms: CreditCardTerms(
          workspace: workspace,
          cardId: card.id,
          currency: twd,
          closingDay: 28,
          dueDay: 15,
        ),
      ),
    );
  });

  tearDown(() {
    final base = root.resolveSymbolicLinksSync();
    final target = work.resolveSymbolicLinksSync();
    if (!target.startsWith('$base${Platform.pathSeparator}')) {
      throw StateError('Unsafe synthetic cleanup');
    }
    work.deleteSync(recursive: true);
  });

  test('pending, cancellation and replay never create spend', () async {
    final charge = pending();
    final creation = op();
    final cancellation = op();
    await store.withSession((session) async {
      final before = await session.snapshot();
      final created = await session.authorizeCardPurchase(charge, creation);
      expect(created.state, CardAuthorizationState.pending);
      expect(
        (await session.authorizeCardPurchase(charge, creation)).state,
        CardAuthorizationState.pending,
      );
      expect(
        (await session.cardAuthorizations(workspace)).single.charge.id,
        charge.id,
      );
      final cancelled = await session.cancelCardAuthorization(
        workspace: workspace,
        chargeId: charge.id,
        operation: cancellation,
      );
      expect(cancelled.state, CardAuthorizationState.cancelled);
      expect(
        (await session.cancelCardAuthorization(
          workspace: workspace,
          chargeId: charge.id,
          operation: cancellation,
        )).state,
        CardAuthorizationState.cancelled,
      );
      final attempted = purchase(Money.parse(twd, '330'));
      final priorFailure = await session.snapshot();
      await expectLater(
        session.postAuthorizedCardPurchase(
          chargeId: charge.id,
          purchase: attempted,
          settledAmount: Money.parse(twd, '325'),
          fee: Money.parse(twd, '5'),
        ),
        throwsFormatException,
      );
      expect(await session.snapshot(), priorFailure);
      expect(await session.accounts(workspace), hasLength(1));
      expect(
        (await session.accounts(workspace)).single.balance.minorUnits,
        BigInt.zero,
      );
      expect(before, isNot(await session.snapshot()));
    });
  });

  test('foreign estimate posts once in card currency with fee', () async {
    final charge = pending();
    final posted = purchase(Money.parse(twd, '330'));
    await store.withSession((session) async {
      await session.authorizeCardPurchase(charge, op());
      final result = await session.postAuthorizedCardPurchase(
        chargeId: charge.id,
        purchase: posted,
        settledAmount: Money.parse(twd, '325'),
        fee: Money.parse(twd, '5'),
      );
      expect(result.replayed, isFalse);
      expect(
        (await session.postAuthorizedCardPurchase(
          chargeId: charge.id,
          purchase: posted,
          settledAmount: Money.parse(twd, '325'),
          fee: Money.parse(twd, '5'),
        )).replayed,
        isTrue,
      );
      final fact = (await session.cardAuthorizations(workspace)).single;
      expect(fact.state, CardAuthorizationState.posted);
      expect(fact.charge.ledgerEventId, posted.id);
      expect(
        (await session.accounts(workspace)).single.balance,
        Money.parse(twd, '-330'),
      );
      final before = await session.snapshot();
      await expectLater(
        session.postAuthorizedCardPurchase(
          chargeId: charge.id,
          purchase: posted,
          settledAmount: Money.parse(twd, '324'),
          fee: Money.parse(twd, '6'),
        ),
        throwsA(isA<CreditCardException>()),
      );
      expect(await session.snapshot(), before);
    });
    final tables =
        (jsonDecode(utf8.decode(await store.snapshot())) as Map)['tables']
            as Map;
    expect(tables['card_authorizations'], hasLength(1));
    expect(tables['card_authorization_resolutions'], hasLength(1));
    expect(tables['card_posted_charges'], hasLength(1));
    expect(tables['events'], hasLength(2));
  });

  test(
    'reusing authorization operation cannot leave a Ledger purchase',
    () async {
      final charge = pending();
      final creation = op();
      await store.withSession((session) async {
        await session.authorizeCardPurchase(charge, creation);
        final before = await session.snapshot();
        final attempted = purchase(
          Money.parse(twd, '10'),
          key: OperationKey(workspace, creation),
        );
        await expectLater(
          session.postAuthorizedCardPurchase(
            chargeId: charge.id,
            purchase: attempted,
            settledAmount: Money.parse(twd, '10'),
            fee: Money(twd, BigInt.zero),
          ),
          throwsFormatException,
        );
        expect(await session.snapshot(), before);
        expect(
          (await session.cardAuthorizations(workspace)).single.state,
          CardAuthorizationState.pending,
        );
      });
    },
  );
}
