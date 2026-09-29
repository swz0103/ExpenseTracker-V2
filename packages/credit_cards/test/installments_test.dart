import 'package:credit_cards/credit_cards.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:test/test.dart';

void main() {
  final twd = Currency('TWD', 2);
  CardInstallmentSchedule schedule({
    String principal = '100.01',
    String fee = '1.01',
    int count = 3,
    BusinessDate? firstClose,
  }) => CardInstallmentSchedule(
    purchaseEventId: PublicId.generate(),
    workspace: WorkspaceId(PublicId.generate()),
    cardId: PublicId.generate(),
    principal: Money.parse(twd, principal),
    fixedFee: Money.parse(twd, fee),
    firstClose: firstClose ?? BusinessDate(2028, 1, 31),
    count: count,
  );

  test('monthly schedule allocates principal and explicit fee with final remainder', () {
    final parts = schedule().installments;
    expect(parts.map((part) => part.closesOn.toString()), [
      '2028-01-31',
      '2028-02-29',
      '2028-03-31',
    ]);
    expect(parts.map((part) => part.principal.majorText), [
      '33.33',
      '33.33',
      '33.35',
    ]);
    expect(parts.map((part) => part.fee.majorText), ['0.33', '0.33', '0.35']);
    expect(
      parts.fold<BigInt>(BigInt.zero, (sum, part) => sum + part.due.minorUnits),
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
      () => schedule(firstClose: BusinessDate(9999, 12, 31)),
      throwsA(isA<CreditCardException>()),
    );
    expect(
      () => CardInstallmentSchedule(
        purchaseEventId: PublicId.generate(),
        workspace: WorkspaceId(PublicId.generate()),
        cardId: PublicId.generate(),
        principal: Money.parse(twd, '10'),
        fixedFee: Money.parse(Currency('USD', 2), '1'),
        firstClose: BusinessDate(2028, 1, 31),
        count: 2,
      ),
      throwsA(isA<CreditCardException>()),
    );
    expect(
      () => schedule(principal: '92233720368547758.07', fee: '0.01'),
      throwsA(isA<CreditCardException>()),
    );
  });
}
