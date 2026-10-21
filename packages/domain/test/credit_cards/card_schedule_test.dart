import 'package:core/foundation_values.dart';
import 'package:domain/credit_cards.dart';
import 'package:test/test.dart';

import 'fails.dart';

void main() {
  test('month-end closes on actual last day and due date is next month', () {
    final terms = CardSchedule(closingDay: 31, dueDay: 15);
    final feb = terms.cycleFor(BusinessDate(2028, 2, 29));
    expect(feb.startsAfter, BusinessDate(2028, 1, 31));
    expect(feb.closesOn, BusinessDate(2028, 2, 29));
    expect(feb.dueOn, BusinessDate(2028, 3, 15));
    expect(
      terms.cycleFor(BusinessDate(2028, 3, 1)).closesOn,
      BusinessDate(2028, 3, 31),
    );
    expect(
      terms.lastCloseOn(BusinessDate(2028, 3, 1)),
      BusinessDate(2028, 2, 29),
    );
    expect(
      terms.lastCloseOn(BusinessDate(2028, 2, 29)),
      BusinessDate(2028, 2, 29),
    );
  });

  test('an early close is due the same month; later posts roll over', () {
    final early = CardSchedule(closingDay: 5, dueDay: 20);
    final march = early.cycleFor(BusinessDate(2028, 3, 3));
    expect(march.startsAfter, BusinessDate(2028, 2, 5));
    expect(march.closesOn, BusinessDate(2028, 3, 5));
    expect(march.dueOn, BusinessDate(2028, 3, 20));
    final april = early.cycleFor(BusinessDate(2028, 3, 10));
    expect(april.closesOn, BusinessDate(2028, 4, 5));
    expect(april.dueOn, BusinessDate(2028, 4, 20));
    final lateClose = CardSchedule(closingDay: 25, dueDay: 10);
    expect(
      lateClose.cycleFor(BusinessDate(2028, 3, 26)).dueOn,
      BusinessDate(2028, 5, 10),
    );
  });

  test('a new closing day keeps past statements; actual dates win', () {
    final changed = CardSchedule(
      closingDay: 5,
      dueDay: 20,
      history: [
        CardScheduleChange(
          until: BusinessDate(2028, 4, 5),
          closingDay: 25,
          dueDay: 10,
        ),
      ],
    );
    final march = changed.cycleFor(BusinessDate(2028, 3, 10));
    expect(march.startsAfter, BusinessDate(2028, 2, 25));
    expect(march.closesOn, BusinessDate(2028, 3, 25));
    expect(march.dueOn, BusinessDate(2028, 4, 10));
    // The first cycle on the new day is a short one.
    final transition = changed.cycleFor(BusinessDate(2028, 3, 30));
    expect(transition.startsAfter, BusinessDate(2028, 3, 25));
    expect(transition.closesOn, BusinessDate(2028, 4, 5));
    expect(transition.dueOn, BusinessDate(2028, 4, 20));
    final may = changed.cycleFor(BusinessDate(2028, 4, 20));
    expect(may.startsAfter, BusinessDate(2028, 4, 5));
    expect(may.closesOn, BusinessDate(2028, 5, 5));
    expect(
      () => CardSchedule(
        closingDay: 5,
        dueDay: 20,
        history: [
          CardScheduleChange(
            until: BusinessDate(2028, 4, 6),
            closingDay: 25,
            dueDay: 10,
          ),
        ],
      ),
      fails(CreditCardError.invalidInput),
    );

    // The issuer closed March two days late.
    final moved = CardSchedule(
      closingDay: 5,
      dueDay: 20,
      history: changed.history,
      overrides: [
        CardCycleOverride(
          scheduledClose: BusinessDate(2028, 3, 25),
          closesOn: BusinessDate(2028, 3, 27),
          dueOn: BusinessDate(2028, 4, 11),
        ),
      ],
    );
    final actual = moved.cycleFor(BusinessDate(2028, 3, 26));
    expect(actual.closesOn, BusinessDate(2028, 3, 27));
    expect(actual.dueOn, BusinessDate(2028, 4, 11));
    expect(actual.scheduledClose, BusinessDate(2028, 3, 25));
    expect(moved.datesOf(BusinessDate(2028, 3, 25)), (
      BusinessDate(2028, 3, 27),
      BusinessDate(2028, 4, 11),
    ));
    final after = moved.cycleFor(BusinessDate(2028, 3, 28));
    expect(after.startsAfter, BusinessDate(2028, 3, 27));
    expect(
      () => CardSchedule(
        closingDay: 5,
        dueDay: 20,
        history: changed.history,
        overrides: [
          CardCycleOverride(
            scheduledClose: BusinessDate(2028, 3, 24),
            closesOn: BusinessDate(2028, 3, 27),
            dueOn: BusinessDate(2028, 4, 11),
          ),
        ],
      ),
      fails(CreditCardError.invalidInput),
    );
  });

  test('a close moves a week at most and stays before its due date', () {
    expect(
      () => CardCycleOverride(
        scheduledClose: BusinessDate(2028, 3, 25),
        closesOn: BusinessDate(2028, 4, 2),
        dueOn: BusinessDate(2028, 4, 11),
      ),
      fails(CreditCardError.invalidInput),
    );
    expect(
      () => CardSchedule(closingDay: 0, dueDay: 10),
      fails(CreditCardError.invalidInput),
    );
  });
}
