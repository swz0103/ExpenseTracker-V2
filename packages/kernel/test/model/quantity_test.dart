import 'package:kernel/kernel.dart';
import 'package:test/test.dart';

void main() {
  test('a quantity counts 10^12 parts of a unit, exactly (D87)', () {
    expect(quantityScale, BigInt.from(10).pow(12));
    expect(quantityOfUnits(3), BigInt.from(3) * quantityScale);
    expect(quantityOfUnits(-2), -BigInt.two * quantityScale);
    // As many whole units as an int holds: no overflow (r9: 9.3e12
    // shares wrapped at the old millionth's scale).
    final huge = quantityOfUnits(5000000000000000);
    expect(huge ~/ quantityScale, BigInt.from(5000000000000000));
    expect(keepable(huge), isTrue);
    expect(keepable(maxQuantity), isTrue);
    expect(keepable(maxQuantity + BigInt.one), isFalse);
    expect(keepable(-maxQuantity - BigInt.one), isFalse);
    expect(noQuantity, BigInt.zero);
  });

  test('whole units round half away from zero', () {
    BigInt q(String parts) => BigInt.parse(parts);
    expect(wholeUnits(q('1499999999999')), 1);
    expect(wholeUnits(q('1500000000000')), 2);
    expect(wholeUnits(q('-1500000000000')), -2);
    expect(wholeUnits(q('-1499999999999')), -1);
    expect(wholeUnits(BigInt.zero), 0);
  });
}
