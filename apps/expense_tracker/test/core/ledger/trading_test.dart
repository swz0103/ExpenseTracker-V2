import 'package:expense_tracker/src/core/ledger/trading.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bond ETFs are sold without the securities tax while exempt', () {
    final day = DateTime.utc(2026, 10, 27);
    expect(saleTax('2330', 100000, 100, day), 300);
    expect(saleTax('0050', 100000, 1000, day), 100);
    expect(saleTax('00679B', 100000, 3000, day), 0);
  });

  test('a dividend of NT\$20,000 or more pays the 2.11% premium', () {
    final day = DateTime.utc(2026, 10, 2);
    expect(dividendPremium(19999, day), 0);
    expect(dividendPremium(20000, day), 422);
    expect(dividendPremium(30000, day), 633);
  });
}
