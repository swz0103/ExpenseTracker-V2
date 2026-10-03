import 'package:credit_cards/credit_cards.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:test/test.dart';

void main() {
  final twd = Currency('TWD', 2);
  CardInstallmentSchedule schedule({
    String principal = '100.01',
    String fee = '1.01',
    int count = 3,
    BusinessDate? firstScheduledClose,
  }) => CardInstallmentSchedule(
    purchaseEventId: PublicId.generate(),
    workspace: WorkspaceId(PublicId.generate()),
    cardId: PublicId.generate(),
    principal: Money.parse(twd, principal),
    fixedFee: Money.parse(twd, fee),
    firstScheduledClose: firstScheduledClose ?? BusinessDate(2028, 1, 31),
    closingDay: 31,
    count: count,
  );

  test('monthly schedule spreads principal and fee remainders from the first', () {
    final parts = schedule().installments;
    expect(parts.map((part) => part.scheduledClose.toString()), [
      '2028-01-31',
      '2028-02-29',
      '2028-03-31',
    ]);
    expect(parts.map((part) => part.principal.majorText), [
      '33.34',
      '33.34',
      '33.33',
    ]);
    expect(parts.map((part) => part.fee.majorText), ['0.34', '0.34', '0.33']);
    expect(
      parts.fold<BigInt>(
        BigInt.zero,
        (sum, part) => sum + part.projectedCharge.minorUnits,
      ),
      Money.parse(twd, '101.02').minorUnits,
    );
  });

  test('rejects nonpositive, mismatched, or impossible schedule', () {
    expect(
      () => schedule(principal: '0.01'),
      throwsA(isA<CreditCardException>()),
    );
    expect(() => schedule(fee: '-0.01'), throwsA(isA<CreditCardException>()));
    expect(() => schedule(count: 1), throwsA(isA<CreditCardException>()));
    expect(() => schedule(count: 121), throwsA(isA<CreditCardException>()));
    expect(
      () => schedule(firstScheduledClose: BusinessDate(9999, 12, 31)),
      throwsA(isA<CreditCardException>()),
    );
    expect(
      () => CardInstallmentSchedule(
        purchaseEventId: PublicId.generate(),
        workspace: WorkspaceId(PublicId.generate()),
        cardId: PublicId.generate(),
        principal: Money.parse(twd, '10'),
        fixedFee: Money.parse(Currency('USD', 2), '1'),
        firstScheduledClose: BusinessDate(2028, 1, 31),
        closingDay: 31,
        count: 2,
      ),
      throwsA(isA<CreditCardException>()),
    );
    expect(
      () => schedule(principal: '92233720368547758.07', fee: '0.01'),
      throwsA(isA<CreditCardException>()),
    );
  });

  test('nominal 31st returns after a leap-February first cycle', () {
    final parts = schedule(firstScheduledClose: BusinessDate(2028, 2, 29))
        .installments;
    expect(parts.map((part) => part.scheduledClose.toString()), [
      '2028-02-29',
      '2028-03-31',
      '2028-04-30',
    ]);
    expect(
      () => schedule(firstScheduledClose: BusinessDate(2028, 2, 28)),
      throwsA(isA<CreditCardException>()),
    );
  });

  test('versioned plan round-trips and rejects tampering', () {
    const codec = CardInstallmentScheduleCodec();
    final original = schedule();
    final encoded = codec.encode(original);
    final decoded = codec.decode(encoded);
    expect(codec.encode(decoded), encoded);
    expect(decoded.installments.last.projectedCharge.majorText, '33.66');
    expect(
      () => codec.decode(encoded.replaceFirst('"format":1', '"format":2')),
      throwsFormatException,
    );
    expect(
      () => codec.decode(
        encoded.replaceFirst(
          '"principalMinor":"10001"',
          '"principalMinor":"010001"',
        ),
      ),
      throwsFormatException,
    );
    expect(
      () => codec.decode(encoded.replaceFirst('"count":3', '"count":0')),
      throwsFormatException,
    );
  });
}
