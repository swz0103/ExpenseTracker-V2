import 'package:credit_cards/credit_cards.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:test/test.dart';

void main() {
  final space = WorkspaceId(PublicId.generate());
  final card = PublicId.generate();
  final twd = Currency('TWD', 2);
  final usd = Currency('USD', 2);
  final terms = CreditCardTerms(
    workspace: space,
    cardId: card,
    currency: twd,
    closingDay: 31,
    dueDay: 15,
    limit: Money.parse(twd, '10000'),
  );

  test('month-end closes on actual last day and due date is next month', () {
    final feb = terms.scheduledCycleFor(BusinessDate(2028, 2, 29));
    expect(feb.startsAfter, BusinessDate(2028, 1, 31));
    expect(feb.closesOn, BusinessDate(2028, 2, 29));
    expect(feb.dueOn, BusinessDate(2028, 3, 15));
    expect(
      terms.scheduledCycleFor(BusinessDate(2028, 3, 1)).closesOn,
      BusinessDate(2028, 3, 31),
    );
  });

  test('pending FX estimate is excluded; posted amount replaces it', () {
    final pending = CardCharge.pending(
      id: PublicId.generate(),
      workspace: space,
      cardId: card,
      kind: CardChargeKind.purchase,
      authorizedOn: BusinessDate(2028, 2, 20),
      authorizedAmount: Money.parse(usd, '10'),
    );
    final cycle = terms.scheduledCycleFor(BusinessDate(2028, 2, 20));
    final before = CardStatement.calculate(
      terms: terms,
      cycle: cycle,
      charges: [pending],
      payments: [],
    );
    expect(before.pendingCount, 1);
    expect(before.remainingDue.majorText, '0.00');
    final posted = pending.post(
      postedOn: BusinessDate(2028, 2, 22),
      settledAmount: Money.parse(twd, '321'),
      fee: Money.parse(twd, '5'),
      ledgerEventId: PublicId.generate(),
    );
    final after = CardStatement.calculate(
      terms: terms,
      cycle: cycle,
      charges: [posted],
      payments: [],
    );
    expect(after.pendingCount, 0);
    expect(after.purchases.majorText, '321.00');
    expect(after.fees.majorText, '5.00');
    expect(after.remainingDue.majorText, '326.00');
    expect(
      () => posted.post(
        postedOn: BusinessDate(2028, 2, 23),
        settledAmount: Money.parse(twd, '321'),
        fee: Money.parse(twd, '0'),
        ledgerEventId: PublicId.generate(),
      ),
      throwsA(isA<CreditCardException>()),
    );
  });

  test('cross-cycle refund and partial payment change due, not spending', () {
    CardCharge posted(
      CardChargeKind kind,
      BusinessDate date,
      String amount, {
      PublicId? original,
    }) =>
        CardCharge.pending(
          id: PublicId.generate(),
          workspace: space,
          cardId: card,
          kind: kind,
          authorizedOn: date,
          authorizedAmount: Money.parse(twd, amount),
          originalChargeId: original,
        ).post(
          postedOn: date,
          settledAmount: Money.parse(twd, amount),
          fee: Money.parse(twd, '0'),
          ledgerEventId: PublicId.generate(),
        );
    final purchase = posted(
      CardChargeKind.purchase,
      BusinessDate(2028, 2, 20),
      '100',
    );
    final refund = posted(
      CardChargeKind.refund,
      BusinessDate(2028, 3, 2),
      '30',
      original: purchase.id,
    );
    final feb = terms.scheduledCycleFor(BusinessDate(2028, 2, 20));
    final march = terms.scheduledCycleFor(BusinessDate(2028, 3, 2));
    final payment = CardPayment(
      id: PublicId.generate(),
      workspace: space,
      cardId: card,
      statementClose: feb.closesOn,
      postedOn: BusinessDate(2028, 3, 5),
      amount: Money.parse(twd, '40'),
      ledgerEventId: PublicId.generate(),
    );
    final first = CardStatement.calculate(
      terms: terms,
      cycle: feb,
      charges: [purchase, refund],
      payments: [payment],
    );
    expect(first.purchases.majorText, '100.00');
    expect(first.refunds.majorText, '0.00');
    expect(first.payments.majorText, '40.00');
    expect(first.remainingDue.majorText, '60.00');
    final next = CardStatement.calculate(
      terms: terms,
      cycle: march,
      charges: [purchase, refund],
      payments: [payment],
    );
    expect(next.purchases.majorText, '0.00');
    expect(next.refunds.majorText, '30.00');
    expect(next.remainingDue.majorText, '0.00');
    expect(next.credit.majorText, '30.00');
  });

  test('pending from another cycle is excluded and orphan refund rejected', () {
    final feb = terms.scheduledCycleFor(BusinessDate(2028, 2, 20));
    final future = CardCharge.pending(
      id: PublicId.generate(),
      workspace: space,
      cardId: card,
      kind: CardChargeKind.purchase,
      authorizedOn: BusinessDate(2028, 3, 2),
      authorizedAmount: Money.parse(twd, '10'),
    );
    final summary = CardStatement.calculate(
      terms: terms,
      cycle: feb,
      charges: [future],
      payments: [],
    );
    expect(summary.pendingCount, 0);
    final orphan = CardCharge.pending(
      id: PublicId.generate(),
      workspace: space,
      cardId: card,
      kind: CardChargeKind.refund,
      authorizedOn: BusinessDate(2028, 2, 20),
      authorizedAmount: Money.parse(twd, '1'),
      originalChargeId: PublicId.generate(),
    );
    expect(
      () => CardStatement.calculate(
        terms: terms,
        cycle: feb,
        charges: [orphan],
        payments: [],
      ),
      throwsA(isA<CreditCardException>()),
    );
  });

  test('refunds across cycles cannot exceed the settled purchase', () {
    final purchase =
        CardCharge.pending(
          id: PublicId.generate(),
          workspace: space,
          cardId: card,
          kind: CardChargeKind.purchase,
          authorizedOn: BusinessDate(2028, 2, 20),
          authorizedAmount: Money.parse(twd, '100'),
        ).post(
          postedOn: BusinessDate(2028, 2, 21),
          settledAmount: Money.parse(twd, '90'),
          fee: Money.parse(twd, '0'),
          ledgerEventId: PublicId.generate(),
        );
    CardCharge refund(String amount, BusinessDate day) =>
        CardCharge.pending(
          id: PublicId.generate(),
          workspace: space,
          cardId: card,
          kind: CardChargeKind.refund,
          authorizedOn: day,
          authorizedAmount: Money.parse(twd, amount),
          originalChargeId: purchase.id,
        ).post(
          postedOn: day,
          settledAmount: Money.parse(twd, amount),
          fee: Money.parse(twd, '0'),
          ledgerEventId: PublicId.generate(),
        );
    final first = refund('40', BusinessDate(2028, 3, 2));
    final second = refund('50', BusinessDate(2028, 4, 2));
    final cycle = terms.scheduledCycleFor(BusinessDate(2028, 4, 2));
    expect(
      CardStatement.calculate(
        terms: terms,
        cycle: cycle,
        charges: [purchase, first, second],
        payments: [],
      ).refunds.majorText,
      '50.00',
    );
    expect(
      () => CardStatement.calculate(
        terms: terms,
        cycle: cycle,
        charges: [
          purchase,
          first,
          second,
          refund('0.01', BusinessDate(2028, 4, 3)),
        ],
        payments: [],
      ),
      throwsA(isA<CreditCardException>()),
    );
    expect(
      () => CardStatement.calculate(
        terms: terms,
        cycle: cycle,
        charges: [purchase, refund('1', BusinessDate(2028, 2, 20))],
        payments: [],
      ),
      throwsA(isA<CreditCardException>()),
    );
  });

  test('duplicate Ledger event and wrong workspace fail closed', () {
    final cycle = terms.scheduledCycleFor(BusinessDate(2028, 2, 20));
    final event = PublicId.generate();
    CardCharge charge(PublicId id, WorkspaceId owner) =>
        CardCharge.pending(
          id: id,
          workspace: owner,
          cardId: card,
          kind: CardChargeKind.purchase,
          authorizedOn: BusinessDate(2028, 2, 20),
          authorizedAmount: Money.parse(twd, '1'),
        ).post(
          postedOn: BusinessDate(2028, 2, 20),
          settledAmount: Money.parse(twd, '1'),
          fee: Money.parse(twd, '0'),
          ledgerEventId: event,
        );
    expect(
      () => CardStatement.calculate(
        terms: terms,
        cycle: cycle,
        charges: [
          charge(PublicId.generate(), space),
          charge(PublicId.generate(), space),
        ],
        payments: [],
      ),
      throwsA(isA<CreditCardException>()),
    );
    expect(
      () => CardStatement.calculate(
        terms: terms,
        cycle: cycle,
        charges: [
          charge(PublicId.generate(), WorkspaceId(PublicId.generate())),
        ],
        payments: [],
      ),
      throwsA(isA<CreditCardException>()),
    );
  });
}
