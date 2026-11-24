import 'package:expense_tracker/src/core/ledger/models/models.dart';
import 'package:expense_tracker/src/core/ledger/services/recurring_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/book.dart';

const _rent = Recurring(
  id: 'rent',
  name: '房租',
  amount: 12000,
  day: 1,
  account: 'bank',
  category: '居家',
);

const _phone = Recurring(
  id: 'phone',
  name: '電話費',
  amount: 500,
  day: 20,
  account: 'bank',
  category: '居家',
);

void main() {
  test('a day that came and was not booked is due', () {
    final book = Book(recurring: [_rent, _phone]);
    expect(book.recurringService.pendingDate(_rent), DateTime.utc(2026, 10, 1));
    expect(book.recurringService.due, [_rent]);
    expect(book.recurringService.upcoming, [_phone]);
    expect(book.recurringService.nextDate(_phone), DateTime.utc(2026, 10, 20));
  });

  test('a booked day is no longer due; the next is next month', () {
    final booked = entry(
      'r1',
      recurring: 'rent',
      amount: 12000,
      date: DateTime.utc(2026, 10, 1),
    );
    final book = Book(recurring: [_rent], entries: [booked]);
    expect(book.recurringService.due, isEmpty);
    expect(book.recurringService.nextDate(_rent), DateTime.utc(2026, 11, 1));
    expect(book.recurringService.dueDayOf(booked), DateTime.utc(2026, 10, 1));
  });

  test('a booking is dated its pending day and carries the item', () {
    final book = Book(recurring: [_rent]);
    final e = book.recurringService.booking(_rent);
    expect(
      (e.date, e.amount, e.recurring, e.note),
      (DateTime.utc(2026, 10, 1), 12000, 'rent', '房租'),
    );
    expect(e.home, isNull);
  });

  test('a foreign item is worth its amount at the rate, none without', () {
    final usd = _phone.copyWith(account: 'usd');
    final accounts = const [
      Account('usd', '美元', AccountKind.bank, 0, currency: 'USD'),
    ];
    expect(Book(accounts: accounts).recurringService.worth(usd), 0);
    final rated = Book(accounts: accounts, rates: {'USD': 30});
    // 500 cents is 5 dollars.
    expect(rated.recurringService.worth(usd), 150);
    expect(rated.recurringService.booking(usd).home, 150);
  });

  test('an item paused has nothing pending', () {
    final paused = _rent.copyWith(active: false);
    expect(
      Book(recurring: [paused]).recurringService.pendingDate(paused),
      isNull,
    );
  });

  // Today is Sunday 2026-10-04 (support/book.dart).
  group('unpostedDates', () {
    test('REM-05: the days still to book in a range skip a day let go, and '
        'begin where pendingDate does', () {
      final gym = Recurring(
        id: 'gym',
        name: '健身房',
        amount: 1200,
        day: 5,
        account: 'bank',
        category: '居家',
        start: DateTime.utc(2026, 1, 5),
        skipped: {DateTime.utc(2026, 11, 5)},
      );
      final book = Book(recurring: [gym]);
      final days = book.recurringService.unpostedDates(
        gym,
        from: DateTime.utc(2026, 9, 1),
        to: DateTime.utc(2026, 12, 31),
      );
      // September is before this month with nothing ever booked, so it is
      // not asked for; November 5 was let go.
      expect(days, [DateTime.utc(2026, 10, 5), DateTime.utc(2026, 12, 5)]);
      expect(book.recurringService.pendingDate(gym), days.first);
    });

    test('a booked month moves the days still to book on', () {
      final booked = entry(
        'g1',
        recurring: 'gym',
        date: DateTime.utc(2026, 10, 3),
        amount: 1200,
      );
      const gym = Recurring(
        id: 'gym',
        name: '健身房',
        amount: 1200,
        day: 5,
        account: 'bank',
        category: '居家',
      );
      final book = Book(recurring: [gym], entries: [booked]);
      expect(
        book.recurringService.unpostedDates(
          gym,
          from: DateTime.utc(2026, 10, 1),
          to: DateTime.utc(2026, 11, 30),
        ),
        [DateTime.utc(2026, 11, 5)],
      );
    });

    test('a day missed since the last booking stays, inside the range only; '
        'a paused item has none', () {
      final booked = entry(
        'g1',
        recurring: 'gym',
        date: DateTime.utc(2026, 8, 5),
        amount: 1200,
      );
      const gym = Recurring(
        id: 'gym',
        name: '健身房',
        amount: 1200,
        day: 5,
        account: 'bank',
        category: '居家',
      );
      final service = Book(
        recurring: [gym],
        entries: [booked],
      ).recurringService;
      expect(
        service.unpostedDates(
          gym,
          from: DateTime.utc(2026, 9, 1),
          to: DateTime.utc(2026, 10, 31),
        ),
        [DateTime.utc(2026, 9, 5), DateTime.utc(2026, 10, 5)],
      );
      expect(
        service.unpostedDates(
          gym,
          from: DateTime.utc(2026, 9, 6),
          to: DateTime.utc(2026, 10, 4),
        ),
        isEmpty,
      );
      expect(
        service.unpostedDates(
          gym.copyWith(active: false),
          from: DateTime.utc(2026, 9, 1),
          to: DateTime.utc(2026, 10, 31),
        ),
        isEmpty,
      );
    });
  });

  // CORR-2: recurring items. Today is Sunday 2026-10-04.
  group('matching bookings to days', () {
    Entry booking(String id, DateTime date) =>
        entry(id, recurring: 'rent', amount: 12000, date: date);

    test('LOG-09: a booking moved to the day before still settles its '
        'own period', () {
      final book = Book(
        recurring: [_rent],
        entries: [
          booking('a', DateTime.utc(2026, 9, 1)),
          // October's, moved to September 30.
          booking('b', DateTime.utc(2026, 9, 30)),
        ],
      );
      final service = book.recurringService;
      expect(service.settled(_rent), {
        'a': DateTime.utc(2026, 9, 1),
        'b': DateTime.utc(2026, 10, 1),
      });
      expect(service.pendingDate(_rent), isNull);
      expect(
        service.dueDayOf(book.entries.byId('b')!),
        DateTime.utc(2026, 10, 1),
      );
      expect(service.bookedDays(_rent).keys, [
        DateTime.utc(2026, 9, 1),
        DateTime.utc(2026, 10, 1),
      ]);
    });

    test('a booking on its day takes it first; the rest take the earliest '
        'left in their month', () {
      final book = Book(
        recurring: [_rent],
        entries: [
          booking('early', DateTime.utc(2026, 8, 31)),
          booking('oct', DateTime.utc(2026, 10, 1)),
        ],
      );
      expect(book.recurringService.settled(_rent), {
        'oct': DateTime.utc(2026, 10, 1),
        // The days open from August, the month of the earliest booking.
        'early': DateTime.utc(2026, 8, 1),
      });
      // September was neither booked nor let go.
      expect(
        book.recurringService.pendingDate(_rent),
        DateTime.utc(2026, 9, 1),
      );
    });

    test('the nearest day: the date itself, else the earliest in its '
        'month, else the nearest, the earlier of two as near', () {
      final days = [
        DateTime.utc(2026, 9, 28),
        DateTime.utc(2026, 10, 2),
        DateTime.utc(2026, 10, 20),
      ];
      DateTime? near(DateTime d, [List<DateTime>? among]) =>
          RecurringService.nearestDay(d, among ?? days);
      expect(near(DateTime.utc(2026, 10, 20)), DateTime.utc(2026, 10, 20));
      expect(near(DateTime.utc(2026, 10, 25)), DateTime.utc(2026, 10, 2));
      // Nov 1: none in November; Oct 20 is 12 days off, the nearest.
      expect(near(DateTime.utc(2026, 11, 1)), DateTime.utc(2026, 10, 20));
      // Sep 30 among Oct 2 and Sep 28 only: both 2 days off, the earlier.
      expect(
        near(DateTime.utc(2026, 9, 30), [
          DateTime.utc(2026, 10, 2),
          DateTime.utc(2026, 9, 28),
        ]),
        DateTime.utc(2026, 9, 28),
      );
      expect(near(DateTime.utc(2026, 11, 1), const []), isNull);
    });

    test('D66: a day 恢復 brought back before every booking is due again', () {
      final back = _rent.copyWith(openFrom: DateTime.utc(2026, 7, 1));
      final book = Book(
        recurring: [back],
        entries: [booking('s', DateTime.utc(2026, 9, 1))],
      );
      expect(book.recurringService.pendingDate(back), DateTime.utc(2026, 7, 1));
      // July and August, then October: September is booked.
      expect(
        book.recurringService.unpostedDates(
          back,
          from: DateTime.utc(2000),
          to: DateTime.utc(2026, 10, 31),
        ),
        [
          DateTime.utc(2026, 7, 1),
          DateTime.utc(2026, 8, 1),
          DateTime.utc(2026, 10, 1),
        ],
      );
    });
  });

  group('booking', () {
    test('D66: on the day asked for, not the pending one', () {
      final book = Book(recurring: [_rent]);
      final e = book.recurringService.booking(
        _rent,
        day: DateTime.utc(2026, 9, 1),
      );
      expect(e.date, DateTime.utc(2026, 9, 1));
    });

    test("R5: a foreign day gone by takes no worth at today's rate", () {
      final usd = _rent.copyWith(account: 'usd');
      final book = Book(
        accounts: const [
          Account('usd', '美元', AccountKind.bank, 0, currency: 'USD'),
        ],
        rates: {'USD': 30},
      );
      // October 1 was three days ago: no rate of that day is kept.
      final late = book.recurringService.booking(usd);
      expect((late.date, late.home), (DateTime.utc(2026, 10, 1), null));
      // Today: today's rate. 12000 cents is 120 dollars; × 30 = 3600.
      final now = book.recurringService.booking(
        usd,
        day: DateTime.utc(2026, 10, 4),
      );
      expect(now.home, 3600);
    });
  });

  test('R3: the next day of a yearly item every three years is found', () {
    final rare = Recurring(
      id: 'rare',
      name: '換照',
      amount: 450,
      day: 3,
      account: 'bank',
      category: '居家',
      unit: RepeatUnit.year,
      every: 3,
      start: DateTime.utc(2026, 3, 3),
    );
    final service = Book(recurring: [rare]).recurringService;
    // 2026-03-03, then three years on.
    expect(service.nextDate(rare), DateTime.utc(2029, 3, 3));
    expect(service.nextDate(rare.copyWith(active: false)), isNull);
  });
}
