import 'package:expense_tracker/src/core/messages/trade_messages.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a discount is written as brokers write it', () {
    expect(discountName(10000), '不打折');
    expect(discountName(6000), '6 折');
    expect(discountName(2800), '2.8 折');
    expect(discountName(2850), '2.85 折');
    // 0.2805 of the fee: 2.805折.
    expect(discountName(2805), '2.805 折');
    expect(discountName(1), '0.001 折');
  });

  test('every discount offered has a name and none repeats', () {
    final offered = [for (final row in BrokerDiscountText.rows) ...row];
    expect(offered, [10000, 6000, 5000, 3800, 2800, 2000]);
    expect({for (final d in offered) discountName(d)}, hasLength(6));
  });
}
