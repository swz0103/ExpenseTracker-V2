import 'dart:ui' show Color;

import 'package:core/foundation_values.dart' show BusinessDate;
import 'package:domain/credit_cards.dart' show CardScheduleChange;
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/ledger/record_json.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every record the journal keeps reads back as it was written.
void main() {
  test('an account keeps its card terms and its looks', () {
    final card = Account(
      'card',
      '玉山卡',
      AccountKind.card,
      -1200,
      icon: 'star',
      closingDay: 5,
      dueDay: 20,
      limit: 80000,
      inNetWorth: false,
      closes: {DateTime.utc(2026, 10, 5): DateTime.utc(2026, 10, 7)},
      history: [
        CardScheduleChange(
          until: BusinessDate(2026, 11, 5),
          closingDay: 25,
          dueDay: 10,
        ),
      ],
    );
    final back = accountFromJson(accountToJson(card));
    expect(accountToJson(back), accountToJson(card));
    expect(back.closes, card.closes);
    expect(back.history.single.until, BusinessDate(2026, 11, 5));
    const dollars = Account(
      'usd',
      '美元',
      AccountKind.bank,
      1000,
      currency: 'USD',
      archived: true,
    );
    final usd = accountFromJson(accountToJson(dollars));
    expect((usd.currency, usd.archived, usd.inNetWorth), ('USD', true, true));
  });

  test('categories, budgets and recurring items read back whole', () {
    const pet = Category(
      '寵物',
      'pet',
      Color(0xFF123456),
      parent: '居家生活',
      archived: true,
    );
    final category = categoryFromJson(categoryToJson(pet));
    expect(category.color, pet.color);
    expect((category.parent, category.archived), ('居家生活', true));

    final budget = Budget(
      '#旅遊',
      5000,
      warning: 90,
      carry: true,
      since: DateTime.utc(2026, 10),
    );
    expect(budgetToJson(budgetFromJson(budgetToJson(budget))), {
      'category': '#旅遊',
      'limit': 5000,
      'warning': 90,
      'carry': true,
      'since': '2026-10-01',
    });

    final rent = Recurring(
      id: 'rent',
      name: '房租',
      amount: 12000,
      day: 5,
      account: 'bank',
      category: '居家生活',
      active: false,
      unit: RepeatUnit.week,
      every: 2,
      start: DateTime.utc(2026, 1, 2),
      end: DateTime.utc(2027, 1, 1),
      merchant: '房東',
    );
    final again = recurringFromJson(recurringToJson(rent));
    expect(recurringToJson(again), recurringToJson(rent));
    expect(again.datesIn(2026, 3), rent.datesIn(2026, 3));
  });

  test('a record of the wrong shape is a format error', () {
    expect(
      () => entryFromJson({'id': 'x', 'date': 'soon'}),
      throwsFormatException,
    );
    expect(
      () => accountFromJson({'id': 'x', 'name': 'y', 'kind': 'castle'}),
      throwsFormatException,
    );
    expect(
      () => categoryFromJson({'name': 'x', 'icon': 'y', 'color': 'red'}),
      throwsFormatException,
    );
  });
}
