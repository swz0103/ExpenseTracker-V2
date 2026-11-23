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

  test('D11: the form offers up to 60, the most the write rules keep', () {
    expect(installmentChoices.first, 0);
    expect(installmentChoices.last, 60);
    expect(maxInstallments, 60);
    Entry card(int count) => Entry(
      id: 'tv',
      date: DateTime.utc(2026, 11, 23),
      type: EntryType.expense,
      amount: 60000,
      account: 'card',
      category: '家電',
      installments: count,
    );
    for (final n in installmentChoices) {
      expect(entryShapeIssues(card(n)), isEmpty, reason: '$n');
    }
    expect(entryShapeIssues(card(61)), [isA<InstallmentsOutOfRange>()]);
  });
}
