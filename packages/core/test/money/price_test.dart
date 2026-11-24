import 'package:core/money/price.dart';
import 'package:test/test.dart';

void main() {
  test('a price is taken to 1/10,000', () {
    // 662.05 x 10,000 = 6,620,500; 0.15 x 10,000 = 1,500.
    expect(scaledPrice(662.05), 6620500);
    expect(scaledPrice(0.15), 1500);
    expect(priceScale, 10000);
  });

  test('a product on a half rounds as written, not as a double holds it', () {
    // 2,730 x 662.05 = 1,807,396.5 -> 1,807,397; as doubles it was
    // 1,807,396.4999999998 and rounded down.
    expect(timesPrice(2730, 662.05), 1807397);
    expect(timesPrice(-2730, 662.05), -1807397);
    // 3 x 0.15 = 0.45 -> 0; 50 x 12.01 = 600.5 -> 601.
    expect(timesPrice(3, 0.15), 0);
    expect(timesPrice(50, 12.01), 601);
  });

  test('a price a double holds just below is rounded, not cut '
      '(mutation review 11)', () {
    // 1.005 × 10,000 is 10,049.999999999998 as doubles: 10,050 steps.
    expect(scaledPrice(1.005), 10050);
  });
}
