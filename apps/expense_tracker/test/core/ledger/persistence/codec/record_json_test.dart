import 'package:core/foundation_values.dart' show BusinessDate;
import 'package:domain/credit_cards.dart' show CardScheduleChange;
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/ledger/persistence/codec/record_json.dart';
import 'package:expense_tracker/src/core/ledger/persistence/codec/same_values.dart';
import 'package:expense_tracker/src/core/ledger/persistence/record_version.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every record the data source keeps reads back as it was written.
void main() {
  group('entries read as the book opens', () {
    Map<String, Object?> row(String id) => {
      'id': id,
      'date': '2026-09-04',
      'type': 'expense',
      'amount': 5,
      // Made afresh for each row, as decoding each row's JSON makes them.
      'account': String.fromCharCodes('cash'.codeUnits),
      'merchant': String.fromCharCodes('全聯'.codeUnits),
      'tags': [String.fromCharCodes('家用'.codeUnits)],
    };

    test('share what they repeat through one SameValues', () {
      final same = SameValues();
      final a = entryFromJson(row('a'), null, same);
      final b = entryFromJson(row('b'), null, same);
      expect(identical(a.account, b.account), isTrue);
      expect(identical(a.merchant, b.merchant), isTrue);
      expect(identical(a.tags.single, b.tags.single), isTrue);
      expect(identical(a.date, b.date), isTrue);
      expect(b.date, DateTime.utc(2026, 9, 4));
    });

    test('read alone, keep their own', () {
      final a = entryFromJson(row('a'));
      final b = entryFromJson(row('b'));
      expect(identical(a.account, b.account), isFalse);
      expect(a.account, b.account);
    });

    test('with no tags or parts, have none', () {
      final e = entryFromJson({...row('a')}..remove('tags'));
      expect(e.tags, isEmpty);
      expect(e.parts, isEmpty);
    });
  });

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
    const loan = Account(
      'loan',
      '房貸',
      AccountKind.loan,
      -1280000,
      principal: 2000000,
      place: 3,
      color: 0xFF5B8DB0,
      loan: LoanTerms(
        rate: 215,
        months: 240,
        repay: LoanRepay.principal,
        payFrom: 'bank',
      ),
    );
    final kept = accountFromJson(accountToJson(loan));
    expect((kept.principal, kept.place), (2000000, 3));
    expect(
      (
        kept.color,
        kept.loan?.rate,
        kept.loan?.months,
        kept.loan?.repay,
        kept.loan?.payFrom,
      ),
      (0xFF5B8DB0, 215, 240, LoanRepay.principal, 'bank'),
    );
    expect(accountToJson(usd).containsKey('place'), isFalse);
    expect(accountToJson(usd).containsKey('repay'), isFalse);
  });

  group('D6: a day-trade sale', () {
    Map<String, Object?> row(String type) => {
      'id': 's',
      'date': '2026-10-04',
      'type': type,
      'amount': 100000,
      'account': 'bank',
      'holding': '2330',
      'shares': 1000,
      'dayTrade': true,
    };
    test('is read back as one', () {
      final sale = entryFromJson(row('sell'));
      expect(sale.dayTrade, isTrue);
      expect(entryToJson(sale)['dayTrade'], true);
    });
    test('an older book, without the field, has none', () {
      final old = entryFromJson(row('sell')..remove('dayTrade'));
      expect(old.dayTrade, isFalse);
      expect(entryToJson(old).containsKey('dayTrade'), isFalse);
    });
    test('the field left on what is no longer a sale is not one', () {
      expect(entryFromJson(row('buy')).dayTrade, isFalse);
    });
  });

  group('D7: an account keeps its own broker discount', () {
    test('read back as written', () {
      const broker = Account(
        'b',
        '券商交割',
        AccountKind.bank,
        0,
        brokerDiscount: 2800,
      );
      expect(accountToJson(broker)['brokerDiscount'], 2800);
      expect(accountFromJson(accountToJson(broker)).brokerDiscount, 2800);
    });
    test('an account of an older book, without it, takes the default', () {
      final old = accountFromJson({
        'id': 'b',
        'name': '銀行',
        'kind': 'bank',
        'opening': 0,
      });
      expect(old.brokerDiscount, isNull);
      expect(accountToJson(old).containsKey('brokerDiscount'), isFalse);
    });
    test('one outside the range is no discount, and takes the default', () {
      Account read(int points) => accountFromJson({
        'id': 'b',
        'name': '銀行',
        'kind': 'bank',
        'opening': 0,
        'brokerDiscount': points,
      });
      expect(read(0).brokerDiscount, isNull);
      expect(read(10001).brokerDiscount, isNull);
      expect(read(10000).brokerDiscount, 10000);
    });
  });

  test('categories, budgets and recurring items read back whole', () {
    final pet = Category(
      '寵物',
      'pet',
      0xFF123456,
      parent: '居家生活',
      archived: true,
      place: 3,
    );
    final category = categoryFromJson(categoryToJson(pet));
    expect(category.color, pet.color);
    expect((category.parent, category.archived), ('居家生活', true));
    expect(category.place, 3);

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

  test('D80: a transfer kept with no category reads under 轉帳; a '
      'recurring item reads back with the day 恢復 brought back', () {
    final kept = <String, Object?>{
      'id': 't',
      'date': '2026-10-01',
      'type': 'transfer',
      'amount': 100,
      'account': 'bank',
      'to': 'cash',
    };
    expect(entryFromJson(upgradeRecord('entry', kept)).category, '轉帳');
    final trashed = upgradeRecord('trash', {'on': '2026-10-02', 'entry': kept});
    expect(trashedFromJson(trashed).entry.category, '轉帳');
    // Spending with no category, and a row already with one, as they are.
    final spend = {...kept, 'type': 'expense'};
    expect(identical(upgradeRecord('entry', spend), spend), isTrue);
    final item = Recurring(
      id: 'r',
      name: 'r',
      amount: 1,
      day: 5,
      account: 'bank',
      category: '居家',
      openFrom: DateTime.utc(2026, 6, 5),
    );
    final json = recurringToJson(item);
    expect(json['openFrom'], '2026-06-05');
    expect(recurringFromJson(json).openFrom, DateTime.utc(2026, 6, 5));
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

  test('a part of a split with no category is refused, not left blank', () {
    Map<String, Object?> entry(Object parts) => {
      'id': 'x',
      'date': '2026-10-01',
      'type': 'expense',
      'amount': 100,
      'account': 'a',
      'parts': parts,
    };
    expect(
      () => entryFromJson(
        entry([
          {'amount': 100},
        ]),
      ),
      throwsFormatException,
    );
    expect(
      () => entryFromJson(
        entry([
          {'name': '飲食'},
        ]),
      ),
      throwsFormatException,
    );
    // Either the name or the category's id will do.
    expect(
      entryFromJson(
        entry([
          {'name': '飲食', 'amount': 100},
        ]),
      ).parts,
      [('飲食', 100)],
    );
    expect(
      entryFromJson(
        entry([
          {'categoryId': 'c1', 'amount': 100},
        ]),
      ).parts,
      [('c1', 100)],
    );
  });

  group('D52: an entry\'s mark', () {
    Map<String, Object?> row(Object? mark) => {
      'id': 'r',
      'date': '2026-10-04',
      'type': 'income',
      'amount': 40,
      'account': 'card',
      'mark': ?mark,
    };
    test('is read back as written', () {
      final reward = entryFromJson(row('reward'));
      expect(reward.mark, EntryMark.reward);
      expect(entryToJson(reward)['mark'], 'reward');
    });
    test('none is kept as no field; one this version does not know reads '
        'as none', () {
      expect(
        entryToJson(entryFromJson(row(null))).containsKey('mark'),
        isFalse,
      );
      expect(entryFromJson(row('later')).mark, isNull);
    });
  });
}
