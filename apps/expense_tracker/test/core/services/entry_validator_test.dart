import 'package:expense_tracker/src/core/ledger/models/models.dart';
import 'package:expense_tracker/src/core/ledger/services/entry_validation_failure.dart';
import 'package:expense_tracker/src/core/messages/validation_messages.dart';
import 'package:flutter_test/flutter_test.dart';

import 'book.dart';

void main() {
  final accounts = const [
    Account('bank', '銀行', AccountKind.bank, 1000),
    Account('card', '卡', AccountKind.card, 0, closingDay: 25, dueDay: 10),
    Account('usd', '美元', AccountKind.bank, 0, currency: 'USD'),
  ];

  String? problem(Entry e, {List<Entry> entries = const []}) => _messageOf(
    Book(accounts: accounts, entries: entries).validator.validate(e),
  );

  test('a plain entry can be kept', () {
    expect(problem(entry('a')), isNull);
  });

  test('an amount of nothing is refused', () {
    expect(problem(entry('a', amount: 0)), '請輸入金額');
  });

  test('a transfer to the same account is refused', () {
    expect(
      problem(entry('a', type: EntryType.transfer, to: 'bank')),
      '轉出與轉入不能是同一個帳戶',
    );
  });

  test('a card cannot send money out', () {
    expect(
      problem(
        entry('a', type: EntryType.transfer, account: 'card', to: 'bank'),
      ),
      '信用卡不能轉出，請記成支出',
    );
  });

  test('a foreign spending needs its worth in NT\$ until there is a rate', () {
    expect(problem(entry('a', account: 'usd')), '還沒有匯率，請輸入折合台幣的金額');
  });

  test('a refund cannot be more than is left to refund', () {
    final bought = entry('bought', amount: 500);
    expect(
      problem(
        entry('back', type: EntryType.income, amount: 600, refundOf: 'bought'),
        entries: [bought],
      ),
      '超過可退金額 500',
    );
  });

  test('selling shares not held is refused', () {
    final sale = Entry(
      id: 's',
      date: day,
      type: EntryType.sell,
      amount: 1000,
      account: 'bank',
      holding: '2330',
      shares: 1,
    );
    expect(problem(sale), '賣出股數超過持股');
  });
}

String? _messageOf(EntryValidationFailure? failure) =>
    failure == null ? null : validationMessage(failure);
