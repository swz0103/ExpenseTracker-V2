import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/messages/installment_messages.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('an even plan names one amount for every period', () {
    expect(installmentPlan(9000, 3), '3 期 · 每期 3,000');
    expect(installmentPlan(12000, 12), '12 期 · 每期 1,000');
  });

  test('an uneven plan puts the remainder in the first period', () {
    // Shown once as 每期 3,333, three short of what the first one bills.
    expect(installmentPlan(10001, 3), '3 期 · 首期 3,335，其後每期 3,333');
    expect(installmentPlan(1000, 6), '6 期 · 首期 170，其後每期 166');
  });

  test('the amounts shown add up to what was spent', () {
    for (final total in [1, 999, 10001, 123457]) {
      for (final count in [1, 2, 3, 6, 12, 24]) {
        final amounts = installmentAmounts(total, count);
        expect(amounts.fold(0, (a, b) => a + b), total);
        expect(amounts, hasLength(count < 2 ? 1 : count));
      }
    }
  });

  test('amounts are written as asked, such as hidden', () {
    expect(installmentPlan(9000, 3, money: (_) => '••••'), '3 期 · 每期 ••••');
  });
}
