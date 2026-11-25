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

  test("the setting names the full fee's rate from its one source", () {
    expect(
      BrokerDiscountText.detail,
      '記買進、賣出時試算的手續費：成交金額 × 0.1425% × 折扣；帳戶可另設自己的折扣',
    );
  });

  test('the hint and refusals give the two ways of writing one (D86)', () {
    for (final words in [
      BrokerDiscountText.accountHint,
      BrokerDiscountText.outOfRange,
      BrokerDiscountText.unreadable,
    ]) {
      expect(words, contains('6 折或 0.6'));
    }
  });
}
