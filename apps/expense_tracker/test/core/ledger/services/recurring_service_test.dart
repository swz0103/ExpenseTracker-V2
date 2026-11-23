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
}
