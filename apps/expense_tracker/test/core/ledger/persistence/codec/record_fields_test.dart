import 'package:core/foundation_values.dart' show BusinessDate;
import 'package:domain/credit_cards.dart' show CardScheduleChange;
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/ledger/persistence/codec/category_refs.dart';
import 'package:expense_tracker/src/core/ledger/persistence/codec/record_fields.dart';
import 'package:expense_tracker/src/core/ledger/persistence/codec/record_json.dart';
import 'package:flutter_test/flutter_test.dart';

/// The fields the data source keeps of a record it was read with but does
/// not know: every field this version writes must be known, or a record
/// changed here would carry its old value of it along.
void main() {
  final day = DateTime.utc(2026, 10, 4);
  final entry = Entry(
    id: 'e',
    date: day,
    type: EntryType.expense,
    amount: 100,
    account: 'a',
    category: '飲食',
    note: 'n',
    to: 'b',
    holding: '2330',
    shares: 1,
    recurring: 'r',
    merchant: 'm',
    tags: const ['t'],
    parts: const [('飲食', 60), ('交通', 40)],
    fee: 1,
    tax: 1,
    refundOf: 'x',
    installments: 3,
    average: true,
    split: true,
    home: 1,
    received: 1,
    group: 'g',
    dayTrade: true,
  );
  final refs = CategoryRefs([
    Category('飲食', 'food', 1, id: 'c1'),
    Category('交通', 'travel', 1, id: 'c2'),
  ]);

  void allKnown(String collection, Map<String, Object?> json) {
    expect(unknownFields(collection, json), isNull, reason: '$json');
  }

  test('every field written of each kind of record is known', () {
    allKnown(
      'account',
      accountToJson(
        Account(
          'a',
          '卡',
          AccountKind.card,
          1,
          currency: 'USD',
          icon: 'i',
          closingDay: 5,
          dueDay: 20,
          limit: 1,
          archived: true,
          inNetWorth: false,
          principal: 1,
          place: 1,
          color: 1,
          loan: const LoanTerms(
            rate: 1,
            months: 1,
            repay: LoanRepay.even,
            payFrom: 'b',
          ),
          closes: {day: day},
          brokerDiscount: 2800,
          history: [
            CardScheduleChange(
              until: BusinessDate(2026, 11, 5),
              closingDay: 25,
              dueDay: 10,
            ),
          ],
        ),
      ),
    );
    final child = Category(
      '早餐',
      'food',
      1,
      income: true,
      parent: '飲食',
      archived: true,
      place: 1,
    );
    allKnown('category', categoryToJson(child));
    allKnown('category', categoryToJson(child, refs));
    allKnown('entry', entryToJson(entry));
    allKnown('entry', entryToJson(entry, refs));
    final budget = Budget('飲食', 1, warning: 50, carry: true, since: day);
    allKnown('budget', budgetToJson(budget));
    allKnown('budget', budgetToJson(budget, refs));
    final recurring = Recurring(
      id: 'r',
      name: 'n',
      amount: 1,
      day: 1,
      account: 'a',
      category: '飲食',
      active: false,
      unit: RepeatUnit.week,
      every: 2,
      start: day,
      end: day,
      income: true,
      merchant: 'm',
      auto: true,
      skipped: {day},
    );
    allKnown('recurring', recurringToJson(recurring));
    allKnown('recurring', recurringToJson(recurring, refs));
    allKnown('trash', trashedToJson(Trashed(entry, day)));
  });

  test('only what this version does not read is kept', () {
    expect(
      unknownFields('entry', {
        'id': 'e',
        'amount': 1,
        '_v': 2,
        '_at': 3,
        'mood': 'happy',
        'weather': {'sun': true},
      }),
      {
        'mood': 'happy',
        'weather': {'sun': true},
      },
    );
    expect(unknownFields('market', {'odd': 1}), isNull);
  });
}
