import 'package:core/foundation_values.dart';
import 'package:domain/credit_cards.dart';
import 'package:test/test.dart';

import 'fails.dart';

void main() {
  test('the whole remainder goes into the first installment', () {
    expect(installmentShares(10001, 3), [3335, 3333, 3333]);
    expect(installmentShares(9000, 3), [3000, 3000, 3000]);
    expect(installmentShares(5, 1), [5]);
    expect(() => installmentShares(5, 0), fails(CreditCardError.invalidInput));
  });

  test('installments close monthly on the closing day or month end', () {
    final closes = installmentCloses(BusinessDate(2028, 1, 31), 31, 3);
    expect(closes.map((close) => close.toString()), [
      '2028-01-31',
      '2028-02-29',
      '2028-03-31',
    ]);
    // The nominal 31st comes back after a leap February.
    final fromFebruary = installmentCloses(BusinessDate(2028, 2, 29), 31, 3);
    expect(fromFebruary.map((close) => close.toString()), [
      '2028-02-29',
      '2028-03-31',
      '2028-04-30',
    ]);
  });

  test('the first installment is the close of the purchase cycle', () {
    final schedule = CardSchedule(closingDay: 25, dueDay: 10);
    expect(installmentStart(schedule, BusinessDate(2028, 3, 25)), (
      BusinessDate(2028, 3, 25),
      25,
    ));
    expect(installmentStart(schedule, BusinessDate(2028, 3, 26)), (
      BusinessDate(2028, 4, 25),
      25,
    ));
  });

  test('instalments are billed on the days their statements close', () {
    // Closing on the 20th; the September statement closed on the 18th.
    final schedule = CardSchedule(
      closingDay: 20,
      dueDay: 5,
      overrides: [
        CardCycleOverride(
          scheduledClose: BusinessDate(2026, 9, 20),
          closesOn: BusinessDate(2026, 9, 18),
          dueOn: BusinessDate(2026, 10, 5),
        ),
      ],
    );
    // Bought on 9/14: the statement closing on 9/18 bills the first.
    expect(installmentBillingDays(schedule, BusinessDate(2026, 9, 14), 3), [
      BusinessDate(2026, 9, 18),
      BusinessDate(2026, 10, 20),
      BusinessDate(2026, 11, 20),
    ]);
    // Bought on 9/19, after the moved close: the October statement first.
    expect(installmentBillingDays(schedule, BusinessDate(2026, 9, 19), 2), [
      BusinessDate(2026, 10, 20),
      BusinessDate(2026, 11, 20),
    ]);
  });
}
