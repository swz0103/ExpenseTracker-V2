import 'package:expense_tracker/src/core/ledger/models/models.dart';
import 'package:ledger_entries/rules.dart';
import 'package:expense_tracker/src/core/messages/validation_messages.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/book.dart';

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

  Entry trade(
    String id, {
    EntryType type = EntryType.buy,
    String account = 'bank',
    String? holding = '2330',
    int shares = 10,
    int amount = 9000,
    int tax = 0,
  }) => Entry(
    id: id,
    date: day,
    type: type,
    amount: amount,
    account: account,
    holding: holding,
    shares: shares,
    tax: tax,
  );

  test('a trade with no amount asks for shares and price', () {
    expect(problem(trade('t', amount: 0)), '請輸入股數和成交價');
  });

  test('a fee cannot be kept on money sent out of a foreign account', () {
    const usd = Account('usd2', '美元二', AccountKind.bank, 0, currency: 'USD');
    final out = Entry(
      id: 'a',
      date: day,
      type: EntryType.transfer,
      amount: 100,
      account: 'usd',
      to: 'usd2',
      fee: 5,
    );
    final book = Book(accounts: [...accounts, usd]);
    expect(_messageOf(book.validator.validate(out)), '外幣帳戶轉出時不能記手續費');
  });

  test('a card payment keeps no fee', () {
    final pay = Entry(
      id: 'a',
      date: day,
      type: EntryType.transfer,
      amount: 100,
      account: 'bank',
      to: 'card',
      fee: 15,
    );
    expect(problem(pay), '繳卡費不記手續費，請另記一筆支出');
  });

  test('money sent between currencies needs the amount received', () {
    final out = entry('a', type: EntryType.transfer, to: 'usd');
    expect(problem(out), '還沒有匯率，請輸入轉入金額');
  });

  test('a card cannot be paid straight from a foreign account', () {
    final pay = Entry(
      id: 'a',
      date: day,
      type: EntryType.transfer,
      amount: 100,
      account: 'usd',
      to: 'card',
      received: 3200,
    );
    expect(problem(pay), '外幣帳戶不能直接繳卡費');
  });

  test('shares are bought in NT\$ only, and not on a card', () {
    expect(problem(trade('t', account: 'usd')), '投資請用新台幣帳戶');
    expect(problem(trade('t', account: 'card')), '買賣股票要用現金或銀行帳戶付款');
  });

  test('a trade names its stock and its shares', () {
    expect(problem(trade('t', holding: null)), '請選擇投資標的');
    expect(problem(trade('t', shares: 0)), '請輸入股數');
    expect(problem(trade('t')), isNull);
  });

  test('the premium taken cannot be more than the dividend', () {
    final paid = trade('d', type: EntryType.dividend, shares: 0, amount: 100);
    expect(problem(paid), isNull);
    expect(
      problem(
        trade('d', type: EntryType.dividend, shares: 0, tax: 101, amount: 100),
      ),
      '補充保費不能超過股息',
    );
  });

  test('a reduction of shares cannot pass what is held, its own edit '
      'aside', () {
    final bought = trade('buy');
    final cut = trade('cut', type: EntryType.dividend, shares: -11, amount: 0);
    expect(problem(cut, entries: [bought]), '減少的股數超過持股（10 股）');
    final fine = trade('cut', type: EntryType.dividend, shares: -4, amount: 0);
    final book = Book(accounts: accounts, entries: [bought, fine]);
    // Editing the reduction counts its own four shares as still held.
    final more = trade('cut', type: EntryType.dividend, shares: -10, amount: 0);
    expect(book.validator.validate(more, replacing: fine), isNull);
  });

  test('a refund of a card spending goes back to the same card', () {
    final bought = entry('bought', account: 'card', amount: 500);
    expect(
      problem(
        entry('back', type: EntryType.income, amount: 100, refundOf: 'bought'),
        entries: [bought],
      ),
      '信用卡消費的退款要退回同一張卡',
    );
  });

  test('editing a refund counts its own amount as still refundable', () {
    final bought = entry('bought', amount: 500);
    final back = entry(
      'back',
      type: EntryType.income,
      amount: 300,
      refundOf: 'bought',
    );
    final book = Book(accounts: accounts, entries: [bought, back]);
    final raised = entry(
      'back',
      type: EntryType.income,
      amount: 500,
      refundOf: 'bought',
    );
    expect(book.validator.validate(raised, replacing: back), isNull);
    expect(book.validator.validate(raised), isA<Object>());
  });

  test('an import checks shares together, not one sale at a time', () {
    final sale = trade('s', type: EntryType.sell, shares: 1);
    final book = Book(accounts: accounts);
    expect(book.validator.validate(sale, holdings: false), isNull);
    expect(book.validator.holdsWith([trade('b'), sale]), isTrue);
    expect(book.validator.holdsWith([sale]), isFalse);
  });
}

String? _messageOf(RecordIssue? failure) =>
    failure == null ? null : validationMessage(failure);
