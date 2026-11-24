import 'package:kernel/kernel.dart';
import 'package:test/test.dart';

/// The lot arithmetic counts 10^12 parts to a share.
final perShare = BigInt.from(10).pow(12);

int exact(QuantityConversion c) => switch (c) {
  ExactQuantity(:final value) => value,
  _ => throw StateError('not exact: $c'),
};

void main() {
  test('a count of 10^-12 shares becomes millionths, exactly', () {
    // 1.5 shares = 1,500,000,000,000 parts = 1,500,000 millionths.
    expect(exact(quantityOf(BigInt.from(1500000000000), perShare)), 1500000);
    expect(exact(quantityOf(-BigInt.from(2000000), perShare)), -2);
    expect(countOf(1500000, perShare), BigInt.from(1500000000000));
  });

  test('a part finer than a millionth is refused, never rounded', () {
    // 1.0078125 shares: seven decimals.
    expect(quantityOf(BigInt.from(1007812500000), perShare), isA<TooFine>());
    expect(quantityOf(BigInt.from(999999), perShare), isA<TooFine>());
  });

  test('the largest quantity kept, and one past it', () {
    // 9,007,199,254,740,991 millionths = 9,007,199,254.740991 shares.
    final most = BigInt.from(maxQuantity) * BigInt.from(1000000);
    expect(exact(quantityOf(most, perShare)), 9007199254740991);
    expect(exact(quantityOf(-most, perShare)), -9007199254740991);
    expect(quantityOf(most + BigInt.from(1000000), perShare), isA<TooLarge>());
  });

  test('a scale the quantity cannot hold exactly is an error', () {
    expect(
      () => quantityOf(BigInt.one, BigInt.from(1000)),
      throwsArgumentError,
    );
  });

  test('the one rounding of a count finer than a millionth: half to even', () {
    // 2.5 millionths → 2; 3.5 → 4; 2.6 → 3; -2.5 → -2; -3.5 → -4.
    expect(roundedQuantity(BigInt.from(2500000), perShare), 2);
    expect(roundedQuantity(BigInt.from(3500000), perShare), 4);
    expect(roundedQuantity(BigInt.from(2600000), perShare), 3);
    expect(roundedQuantity(BigInt.from(-2500000), perShare), -2);
    expect(roundedQuantity(BigInt.from(-3500000), perShare), -4);
    expect(roundedQuantity(BigInt.from(3000000), perShare), 3);
    expect(
      () => roundedQuantity(BigInt.one, BigInt.from(1000)),
      throwsArgumentError,
    );
    final most = BigInt.from(maxQuantity) * BigInt.from(1000000);
    expect(
      () => roundedQuantity(most + BigInt.from(1000000), perShare),
      throwsArgumentError,
    );
  });

  test('whole units round half away from zero', () {
    expect(wholeUnits(1499999), 1);
    expect(wholeUnits(1500000), 2);
    expect(wholeUnits(-1500000), -2);
    expect(wholeUnits(-1499999), -1);
    expect(wholeUnits(0), 0);
  });
}
