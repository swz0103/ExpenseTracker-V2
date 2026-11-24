import 'package:ledger_entries/model.dart';
import 'package:test/test.dart';

final _day = DateTime.utc(2026, 10, 4);

void main() {
  final drafts = TransferDrafts(main: 'bank', today: _day);

  void expectTransfer(Entry e, String from, String to, int amount) {
    expect(e.type, EntryType.transfer);
    expect(e.category, '轉帳');
    expect(e.id, '');
    expect(e.date, _day);
    expect(e.account, from);
    expect(e.to, to);
    expect(e.amount, amount);
  }

  test('between carries every field it is given', () {
    final e = TransferDrafts.between(
      id: 't1',
      date: _day,
      from: 'cash',
      to: 'usd',
      amount: 300,
      note: '換匯',
      fee: 15,
      received: 1000,
    );
    expect(e.id, 't1');
    expect(e.type, EntryType.transfer);
    expect(e.category, '轉帳');
    expect(e.account, 'cash');
    expect(e.to, 'usd');
    expect(e.amount, 300);
    expect(e.note, '換匯');
    expect(e.fee, 15);
    expect(e.received, 1000);
  });

  test('move: out of the account into the main one, nothing filled in', () {
    expectTransfer(drafts.move('cash'), 'cash', 'bank', 0);
    // The main account itself: from it to itself, to be changed.
    expectTransfer(drafts.move('bank'), 'bank', 'bank', 0);
  });

  test('lend: from the main account to the person', () {
    expectTransfer(drafts.lend('amy'), 'bank', 'amy', 0);
  });

  test('payBack: all that is owed, nothing when it is owed the other way', () {
    expectTransfer(drafts.payBack('amy', owed: 500), 'amy', 'bank', 500);
    expectTransfer(drafts.payBack('amy', owed: -500), 'amy', 'bank', 0);
  });

  test('payInto: from the main account, with an amount and a note', () {
    expectTransfer(drafts.payInto('loan'), 'bank', 'loan', 0);
    final card = drafts.payInto('visa', amount: 1200, note: 'Visa繳款');
    expectTransfer(card, 'bank', 'visa', 1200);
    expect(card.note, 'Visa繳款');
  });
}
