import 'package:credit_cards/credit_cards.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:test/test.dart';

import 'fails.dart';

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
    final feb = terms.cycleFor(BusinessDate(2028, 2, 29));
    expect(feb.startsAfter, BusinessDate(2028, 1, 31));
    expect(feb.closesOn, BusinessDate(2028, 2, 29));
    expect(feb.dueOn, BusinessDate(2028, 3, 15));
    expect(
      terms.cycleFor(BusinessDate(2028, 3, 1)).closesOn,
      BusinessDate(2028, 3, 31),
    );
  });

  test('versioned card settings round-trip and reject non-canonical input', () {
    const codec = CreditCardTermsCodec();
    final revised = CreditCardTerms(
      workspace: space,
      cardId: card,
      currency: twd,
      closingDay: 30,
      dueDay: 12,
      limit: Money.parse(twd, '8000'),
      version: 2,
    );
    final encoded = codec.encode(revised);
    final decoded = codec.decode(encoded);
    expect(codec.encode(decoded), encoded);
    expect(decoded.version, 2);
    expect(decoded.limit!.majorText, '8000.00');
    expect(
      () => codec.decode(encoded.replaceFirst('"version":2', '"version":0')),
      throwsFormatException,
    );
    expect(
      () => codec.decode(
        encoded.replaceFirst('"closingDay":30', '"closingDay":32'),
      ),
      throwsFormatException,
    );
    expect(
      () => codec.decode(
        encoded.replaceFirst('"limitMinor":"800000"', '"limitMinor":"0800000"'),
      ),
      throwsFormatException,
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
    final cycle = terms.cycleFor(BusinessDate(2028, 2, 20));
    final before = CardStatement.calculate(
      terms: terms,
      cycle: cycle,
      charges: [pending],
      payments: [],
    );
    expect(before.pendingCount, 1);
    expect(pending.ledgerEventId, isNull);
    expect(before.purchases.majorText, '0.00');
    expect(before.fees.majorText, '0.00');
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
      fails(CreditCardError.alreadyPosted),
    );
  });

  test('posting retry preserves fact and Ledger identity', () {
    final charge = CardCharge.pending(
      id: PublicId.generate(),
      workspace: space,
      cardId: card,
      kind: CardChargeKind.purchase,
      authorizedOn: BusinessDate(2028, 2, 28),
      authorizedAmount: Money.parse(usd, '10'),
    );
    final eventId = PublicId.generate();
    final postedDate = BusinessDate(2028, 3, 2);
    final settled = Money.parse(twd, '321');
    final fee = Money.parse(twd, '5');
    final posted = charge.post(
      postedOn: postedDate,
      settledAmount: settled,
      fee: fee,
      ledgerEventId: eventId,
    );
    expect(
      identical(
        posted,
        posted.post(
          postedOn: postedDate,
          settledAmount: settled,
          fee: fee,
          ledgerEventId: eventId,
        ),
      ),
      isTrue,
    );
    expect(posted.authorizedAmount, Money.parse(usd, '10'));
    expect(posted.settledAmount, Money.parse(twd, '321'));
    expect(posted.ledgerEventId, eventId);

    void expectConflict({
      BusinessDate? date,
      Money? amount,
      Money? postingFee,
      PublicId? event,
    }) {
      expect(
        () => posted.post(
          postedOn: date ?? postedDate,
          settledAmount: amount ?? settled,
          fee: postingFee ?? fee,
          ledgerEventId: event ?? eventId,
        ),
        throwsA(
          isA<CreditCardException>().having(
            (error) => error.code,
            'code',
            CreditCardError.alreadyPosted,
          ),
        ),
      );
    }

    expectConflict(date: BusinessDate(2028, 3, 3));
    expectConflict(amount: Money.parse(twd, '322'));
    expectConflict(postingFee: Money.parse(twd, '6'));
    expectConflict(event: PublicId.generate());
  });

  test('issuer posting date determines the cycle', () {
    final charge = CardCharge.pending(
      id: PublicId.generate(),
      workspace: space,
      cardId: card,
      kind: CardChargeKind.purchase,
      authorizedOn: BusinessDate(2028, 3, 1),
      authorizedAmount: Money.parse(usd, '10'),
    );
    final feb = terms.cycleFor(BusinessDate(2028, 2, 29));
    final march = terms.cycleFor(BusinessDate(2028, 3, 1));
    final pendingFebruary = CardStatement.calculate(
      terms: terms,
      cycle: feb,
      charges: [charge],
      payments: [],
    );
    final pendingMarch = CardStatement.calculate(
      terms: terms,
      cycle: march,
      charges: [charge],
      payments: [],
    );
    expect(pendingFebruary.remainingDue.majorText, '0.00');
    expect(pendingMarch.remainingDue.majorText, '0.00');
    expect(pendingMarch.pendingCount, 1);

    // The issuer's business date can precede the locally recorded auth date.
    final posted = charge.post(
      postedOn: BusinessDate(2028, 2, 29),
      settledAmount: Money.parse(twd, '300'),
      fee: Money.parse(twd, '0'),
      ledgerEventId: PublicId.generate(),
    );
    final postedFebruary = CardStatement.calculate(
      terms: terms,
      cycle: feb,
      charges: [posted],
      payments: [],
    );
    final postedMarch = CardStatement.calculate(
      terms: terms,
      cycle: march,
      charges: [posted],
      payments: [],
    );
    expect(postedFebruary.purchases.majorText, '300.00');
    expect(postedMarch.purchases.majorText, '0.00');
    expect(postedMarch.pendingCount, 0);
  });

  test('invalid posting leaves authorization pending', () {
    final pending = CardCharge.pending(
      id: PublicId.generate(),
      workspace: space,
      cardId: card,
      kind: CardChargeKind.purchase,
      authorizedOn: BusinessDate(2028, 2, 20),
      authorizedAmount: Money.parse(usd, '10'),
    );
    final eventId = PublicId.generate();
    final date = BusinessDate(2028, 2, 22);
    for (final (amount, fee) in [
      (Money.parse(twd, '0'), Money.parse(twd, '0')),
      (Money.parse(twd, '1'), Money.parse(twd, '-0.01')),
      (Money.parse(twd, '1'), Money.parse(usd, '0')),
    ]) {
      expect(
        () => pending.post(
          postedOn: date,
          settledAmount: amount,
          fee: fee,
          ledgerEventId: eventId,
        ),
        throwsA(
          isA<CreditCardException>().having(
            (error) => error.code,
            'code',
            CreditCardError.invalidInput,
          ),
        ),
      );
    }
    expect(pending.isPosted, isFalse);
    expect(pending.ledgerEventId, isNull);
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
    final feb = terms.cycleFor(BusinessDate(2028, 2, 20));
    final march = terms.cycleFor(BusinessDate(2028, 3, 2));
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
    // February left 60 unpaid; it carries into March (G2-12).
    expect(next.carriedOver.majorText, '60.00');
    expect(next.purchases.majorText, '0.00');
    expect(next.refunds.majorText, '30.00');
    expect(next.remainingDue.majorText, '30.00');
    expect(next.credit.majorText, '0.00');
  });

  test('an early close is due the same month; later posts roll over', () {
    final early = CreditCardTerms(
      workspace: space,
      cardId: card,
      currency: twd,
      closingDay: 5,
      dueDay: 20,
    );
    final march = early.cycleFor(BusinessDate(2028, 3, 3));
    expect(march.startsAfter, BusinessDate(2028, 2, 5));
    expect(march.closesOn, BusinessDate(2028, 3, 5));
    expect(march.dueOn, BusinessDate(2028, 3, 20));
    final april = early.cycleFor(BusinessDate(2028, 3, 10));
    expect(april.closesOn, BusinessDate(2028, 4, 5));
    expect(april.dueOn, BusinessDate(2028, 4, 20));
    final lateClose = CreditCardTerms(
      workspace: space,
      cardId: card,
      currency: twd,
      closingDay: 25,
      dueDay: 10,
    );
    expect(
      lateClose.cycleFor(BusinessDate(2028, 3, 26)).dueOn,
      BusinessDate(2028, 5, 10),
    );
  });

  test('pending from another cycle is excluded and orphan refund rejected', () {
    final feb = terms.cycleFor(BusinessDate(2028, 2, 20));
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
      fails(CreditCardError.invalidInput),
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
    final cycle = terms.cycleFor(BusinessDate(2028, 4, 2));
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
      fails(CreditCardError.invalidInput),
    );
    expect(
      () => CardStatement.calculate(
        terms: terms,
        cycle: cycle,
        charges: [purchase, refund('1', BusinessDate(2028, 2, 20))],
        payments: [],
      ),
      fails(CreditCardError.invalidInput),
    );
  });

  test('duplicate Ledger event and wrong workspace fail closed', () {
    final cycle = terms.cycleFor(BusinessDate(2028, 2, 20));
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
      fails(CreditCardError.duplicateIdentity),
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
      fails(CreditCardError.workspaceMismatch),
    );
  });

  test('statement lines and available credit for the card screens', () {
    CardCharge charge(String amount, {String fee = '0', bool post = true}) {
      final pending = CardCharge.pending(
        id: PublicId.generate(),
        workspace: space,
        cardId: card,
        kind: CardChargeKind.purchase,
        authorizedOn: BusinessDate(2028, 2, 20),
        authorizedAmount: Money.parse(twd, amount),
      );
      if (!post) return pending;
      return pending.post(
        postedOn: BusinessDate(2028, 2, 20),
        settledAmount: Money.parse(twd, amount),
        fee: Money.parse(twd, fee),
        ledgerEventId: PublicId.generate(),
      );
    }

    final plain = charge('100', fee: '1.5');
    final planned = charge('300');
    final waiting = charge('50', post: false);
    final abroad = CardCharge.pending(
      id: PublicId.generate(),
      workspace: space,
      cardId: card,
      kind: CardChargeKind.purchase,
      authorizedOn: BusinessDate(2028, 2, 21),
      authorizedAmount: Money.parse(usd, '20'),
    );
    final feb = terms.cycleFor(BusinessDate(2028, 2, 20));
    final plan = CardInstallmentSchedule(
      purchaseEventId: planned.ledgerEventId!,
      workspace: space,
      cardId: card,
      principal: Money.parse(twd, '300'),
      fixedFee: Money.parse(twd, '0'),
      firstScheduledClose: feb.closesOn,
      closingDay: 31,
      count: 3,
    );
    final payment = CardPayment(
      id: PublicId.generate(),
      workspace: space,
      cardId: card,
      statementClose: feb.closesOn,
      postedOn: BusinessDate(2028, 2, 25),
      amount: Money.parse(twd, '40'),
      ledgerEventId: PublicId.generate(),
    );
    final charges = [plain, planned, waiting, abroad];
    final items = CardStatementItems.select(
      cycle: feb,
      charges: charges,
      payments: [payment],
      plans: [plan],
    );
    expect(items.charges, [plain]);
    expect([for (final part in items.installments) part.number], [1]);
    expect(items.payments, [payment]);

    // 10000 - (100 + 1.5 + 300 + 50 pending) + 40 paid; the USD hold is
    // not counted until it posts.
    final left = remainingCredit(
      terms: terms,
      charges: charges,
      payments: [payment],
    );
    expect(left!.majorText, '9588.50');
    final noLimit = CreditCardTerms(
      workspace: space,
      cardId: card,
      currency: twd,
      closingDay: 31,
      dueDay: 15,
    );
    expect(
      remainingCredit(terms: noLimit, charges: charges, payments: []),
      isNull,
    );
  });

  test('a due date on a weekend or holiday moves to the next banking day', () {
    // 2026-10-10 is a Saturday; the Friday before is a holiday.
    final calendar = BankingCalendar(holidays: {BusinessDate(2026, 10, 9)});
    for (final day in [9, 10, 11, 12]) {
      final due = paymentDueOn(BusinessDate(2026, 10, day), calendar);
      expect(due, BusinessDate(2026, 10, 12));
    }
    final open = paymentDueOn(BusinessDate(2026, 10, 14), calendar);
    expect(open, BusinessDate(2026, 10, 14));
  });

  test('the minimum due is 10% of spending plus installments and fees', () {
    final whole = Currency.of('TWD');
    final card2 = CreditCardTerms(
      workspace: space,
      cardId: card,
      currency: whole,
      closingDay: 25,
      dueDay: 10,
    );
    CardCharge posted(int amount, {int fee = 0}) {
      final pending = CardCharge.pending(
        id: PublicId.generate(),
        workspace: space,
        cardId: card,
        kind: CardChargeKind.purchase,
        authorizedOn: BusinessDate(2026, 10, 3),
        authorizedAmount: Money(whole, BigInt.from(amount)),
      );
      return pending.post(
        postedOn: BusinessDate(2026, 10, 3),
        settledAmount: Money(whole, BigInt.from(amount)),
        fee: Money(whole, BigInt.from(fee)),
        ledgerEventId: PublicId.generate(),
      );
    }

    final cycle = card2.cycleFor(BusinessDate(2026, 10, 3));
    CardStatement statement(List<CardCharge> charges, [int paid = 0]) {
      final payments = [
        if (paid > 0)
          CardPayment(
            id: PublicId.generate(),
            workspace: space,
            cardId: card,
            statementClose: cycle.closesOn,
            postedOn: BusinessDate(2026, 10, 20),
            amount: Money(whole, BigInt.from(paid)),
            ledgerEventId: PublicId.generate(),
          ),
      ];
      return CardStatement.calculate(
        terms: card2,
        cycle: cycle,
        charges: charges,
        payments: payments,
      );
    }

    Money ntd(int units) => Money(whole, BigInt.from(units));
    final charges = [posted(12345, fee: 30)];
    // 30 fee + 10% of 12345 rounded up.
    expect(statement(charges).minimumDue(), ntd(30 + 1235));
    expect(statement(charges).minimumDue(floor: ntd(2000)), ntd(2000));
    expect(statement(charges, 1000).minimumDue(), ntd(265));
    expect(statement(charges, 5000).minimumDue(), ntd(0));
    // Never more than what is owed.
    final small = [posted(500)];
    expect(statement(small).minimumDue(floor: ntd(1000)), ntd(500));
    expect(statement(const []).minimumDue(), ntd(0));
  });

  test('a new closing day keeps past statements; actual dates win', () {
    final base = CreditCardTerms(
      workspace: space,
      cardId: card,
      currency: twd,
      closingDay: 25,
      dueDay: 10,
    );
    final changed = base.reschedule(
      closingDay: 5,
      dueDay: 20,
      from: BusinessDate(2028, 4, 5),
    );
    expect(changed.version, 2);
    final march = changed.cycleFor(BusinessDate(2028, 3, 10));
    expect(march.startsAfter, BusinessDate(2028, 2, 25));
    expect(march.closesOn, BusinessDate(2028, 3, 25));
    expect(march.dueOn, BusinessDate(2028, 4, 10));
    // The first cycle on the new day is a short one.
    final transition = changed.cycleFor(BusinessDate(2028, 3, 30));
    expect(transition.startsAfter, BusinessDate(2028, 3, 25));
    expect(transition.closesOn, BusinessDate(2028, 4, 5));
    expect(transition.dueOn, BusinessDate(2028, 4, 20));
    final may = changed.cycleFor(BusinessDate(2028, 4, 20));
    expect(may.startsAfter, BusinessDate(2028, 4, 5));
    expect(may.closesOn, BusinessDate(2028, 5, 5));
    expect(
      () => base.reschedule(
        closingDay: 5,
        dueDay: 20,
        from: BusinessDate(2028, 4, 6),
      ),
      fails(CreditCardError.invalidInput),
    );

    // The issuer closed March two days late.
    final moved = changed.overrideCycle(
      scheduledClose: BusinessDate(2028, 3, 25),
      closesOn: BusinessDate(2028, 3, 27),
      dueOn: BusinessDate(2028, 4, 11),
    );
    final actual = moved.cycleFor(BusinessDate(2028, 3, 26));
    expect(actual.closesOn, BusinessDate(2028, 3, 27));
    expect(actual.dueOn, BusinessDate(2028, 4, 11));
    expect(actual.scheduledClose, BusinessDate(2028, 3, 25));
    final after = moved.cycleFor(BusinessDate(2028, 3, 28));
    expect(after.startsAfter, BusinessDate(2028, 3, 27));
    expect(
      moved.overrideCycle(scheduledClose: BusinessDate(2028, 3, 25)).overrides,
      isEmpty,
    );
    expect(
      () => changed.overrideCycle(
        scheduledClose: BusinessDate(2028, 3, 24),
        closesOn: BusinessDate(2028, 3, 27),
        dueOn: BusinessDate(2028, 4, 11),
      ),
      fails(CreditCardError.invalidInput),
    );

    const codec = CreditCardTermsCodec();
    final encoded = codec.encode(moved);
    final decoded = codec.decode(encoded);
    expect(codec.encode(decoded), encoded);
    final again = decoded.cycleFor(BusinessDate(2028, 3, 26));
    expect(again.closesOn, BusinessDate(2028, 3, 27));
  });

  test('foreign charges keep their own amount and refund limit', () {
    final dollars = Money.parse(usd, '100');
    final fee = foreignTransactionFee(Money.parse(twd, '3200'));
    expect(fee, Money.parse(twd, '48'));
    final small = foreignTransactionFee(Money.parse(twd, '33.33'));
    expect(small, Money.parse(twd, '0.50'));
    final pending = CardCharge.pending(
      id: PublicId.generate(),
      workspace: space,
      cardId: card,
      kind: CardChargeKind.purchase,
      authorizedOn: BusinessDate(2028, 2, 20),
      authorizedAmount: dollars,
    );
    final purchase = pending.post(
      postedOn: BusinessDate(2028, 2, 21),
      settledAmount: Money.parse(twd, '3200'),
      fee: fee,
      ledgerEventId: PublicId.generate(),
    );
    expect(purchase.foreignAmount, dollars);
    CardCharge refund(Money amount, String local) {
      final credit = CardCharge.pending(
        id: PublicId.generate(),
        workspace: space,
        cardId: card,
        kind: CardChargeKind.refund,
        authorizedOn: BusinessDate(2028, 3, 2),
        authorizedAmount: amount,
        originalChargeId: purchase.id,
      );
      return credit.post(
        postedOn: BusinessDate(2028, 3, 2),
        settledAmount: Money.parse(twd, local),
        fee: Money.parse(twd, '0'),
        ledgerEventId: PublicId.generate(),
      );
    }

    // The rate rose, so the full refund is more than the purchase alone.
    final back = refund(dollars, '3240');
    final left = refundableOf(purchase, [back]);
    expect(left.local, Money.parse(twd, '8'));
    expect(left.foreign, Money.parse(usd, '0'));
    final cycle = terms.cycleFor(BusinessDate(2028, 3, 2));
    final extra = refund(Money.parse(usd, '0.01'), '1');
    expect(
      () => CardStatement.calculate(
        terms: terms,
        cycle: cycle,
        charges: [purchase, back, extra],
        payments: [],
      ),
      fails(CreditCardError.invalidInput),
    );
    final local = refund(Money.parse(twd, '10'), '10');
    expect(
      () => refundableOf(purchase, [local]),
      fails(CreditCardError.currencyMismatch),
    );
  });

  test('issuer fees and credits change what is due', () {
    CardCharge issuer(CardChargeKind kind, String amount) {
      final pending = CardCharge.pending(
        id: PublicId.generate(),
        workspace: space,
        cardId: card,
        kind: kind,
        authorizedOn: BusinessDate(2028, 2, 20),
        authorizedAmount: Money.parse(twd, amount),
      );
      return pending.post(
        postedOn: BusinessDate(2028, 2, 20),
        settledAmount: Money.parse(twd, amount),
        fee: Money.parse(twd, '0'),
        ledgerEventId: PublicId.generate(),
      );
    }

    final charges = [
      issuer(CardChargeKind.fee, '1200'),
      issuer(CardChargeKind.credit, '35'),
    ];
    final feb = CardStatement.calculate(
      terms: terms,
      cycle: terms.cycleFor(BusinessDate(2028, 2, 20)),
      charges: charges,
      payments: [],
    );
    expect(feb.fees.majorText, '1200.00');
    expect(feb.credits.majorText, '35.00');
    expect(feb.remainingDue.majorText, '1165.00');
    final march = CardStatement.calculate(
      terms: terms,
      cycle: terms.cycleFor(BusinessDate(2028, 3, 20)),
      charges: charges,
      payments: [],
    );
    expect(march.carriedOver.majorText, '1165.00');
    final left = remainingCredit(terms: terms, charges: charges, payments: []);
    expect(left!.majorText, '8835.00');
  });
}
