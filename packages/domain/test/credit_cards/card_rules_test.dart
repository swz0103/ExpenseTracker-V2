import 'package:core/foundation_values.dart';
import 'package:domain/credit_cards.dart';
import 'package:test/test.dart';

void main() {
  final due = BusinessDate(2026, 11, 20);
  CardBillStatus on(int day, {int owed = 12800}) => cardBillStatus(
    owed: owed,
    dueOn: due,
    today: BusinessDate(2026, 11, day),
  );

  test('owed before the due day is due, with the days left', () {
    // 11/20 - 11/17 = 3 days.
    expect(on(17), BillDue(due, 3));
    // The day before: 1 day left.
    expect(on(19), BillDue(due, 1));
  });

  test('the due day itself is due today, not overdue', () {
    expect(on(20), BillDueToday(due));
  });

  test('one day after the due day is overdue by one day', () {
    expect(on(21), BillOverdue(due, 1));
    // 11/30 - 11/20 = 10 days.
    expect(on(30), BillOverdue(due, 10));
  });

  test('nothing owed is paid, whatever the day', () {
    expect(on(25, owed: 0), const BillPaid());
    expect(on(25, owed: -5), const BillPaid());
  });

  test('without a closed statement nothing is billed', () {
    expect(
      cardBillStatus(owed: 0, dueOn: null, today: BusinessDate(2026, 11, 1)),
      const BillNotYetBilled(),
    );
  });

  test('days are counted across a month end', () {
    // 12/2 is 12 days after 11/20 (10 days to 11/30, then 2).
    expect(
      cardBillStatus(owed: 1, dueOn: due, today: BusinessDate(2026, 12, 2)),
      BillOverdue(due, 12),
    );
  });
}
