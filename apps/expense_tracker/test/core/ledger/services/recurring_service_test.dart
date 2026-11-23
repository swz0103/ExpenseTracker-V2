import 'package:expense_tracker/src/core/ledger/models/models.dart';
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
}
