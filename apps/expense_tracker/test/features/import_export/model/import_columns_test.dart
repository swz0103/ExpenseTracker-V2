// N4: the app's CSV columns from one definition, the ids that keep
// refunds, groups and recurring links, the day-trade flag and the mark.
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/features/import_export/model/import_export.dart';
import 'package:expense_tracker/src/features/import_export/ui/import_page.dart'
    show importBookOf;
import 'package:flutter_test/flutter_test.dart';

import '../../../baseline/baseline_ledger.dart';

const _accounts = [
  Account('bank', '銀行', AccountKind.bank, 0),
  Account('card', '信用卡', AccountKind.card, 0, closingDay: 20, dueDay: 5),
  Account('recv', '代墊款', AccountKind.receivable, 0),
];

const _rent = Recurring(
  id: 'rent',
  name: '房租',
  amount: 12500,
  day: 1,
  account: 'bank',
  category: '居家',
);

Ledger _book([List<Entry> entries = const []]) => ledgerOf(
  today: day(2026, 10, 20),
  accounts: _accounts,
  categories: [
    Category('飲食', 'food', 0xFF111111),
    Category('居家', 'home', 0xFF222222),
  ],
  recurring: const [_rent],
  entries: entries,
);

Import _read(Ledger ledger, String text) =>
    importCsv(importBookOf(ledger), text, fallback: 'bank');

const _head = '日期,類型,金額,帳戶,轉入帳戶,分類,標記,當沖,代號,股數,編號,退款對象,群組,定期\n';

void main() {
  test('the ids, the refund, the group and the recurring link are kept', () {
    final found = _read(
      _book(),
      '$_head'
      '2026-10-01,支出,900,銀行,,飲食,,,,,a1,,g1,\n'
      '2026-10-01,轉帳,600,銀行,代墊款,,,,,,a2,,g1,\n'
      '2026-10-01,支出,12500,銀行,,居家,,,,,a3,,,rent\n'
      '2026-10-02,退款,100,銀行,,,,,,,a4,a1,,\n',
    );
    expect(found.problems, isEmpty);
    expect([for (final e in found.entries) e.id], ['a1', 'a2', 'a3', 'a4']);
    expect([for (final e in found.entries) e.group], ['g1', 'g1', null, null]);
    expect(found.entries[2].recurring, 'rent');
    expect(found.entries[3].refundOf, 'a1');
  });

  test('a refund goes to the spending it names, not the latest one', () {
    final found = _read(
      _book(),
      '$_head'
      '2026-10-01,支出,500,銀行,,飲食,,,,,old,,,\n'
      '2026-10-03,支出,500,銀行,,飲食,,,,,new,,,\n'
      '2026-10-04,退款,200,銀行,,,,,,,r,old,,\n',
    );
    expect(found.entries.last.refundOf, 'old');
  });

  test('a refund naming a spending in the book refunds it', () {
    final ledger = _book([
      entryOf(
        'p',
        day(2026, 10, 1),
        EntryType.expense,
        500,
        'bank',
        category: '飲食',
      ),
    ]);
    final found = _read(ledger, '${_head}2026-10-02,退款,500,銀行,,,,,,,r,p,,\n');
    expect(found.entries.single.refundOf, 'p');
    // All 500 already given back: a second refund of it has nothing left.
    addImport(ledger.entryCommands, found);
    final again = _read(ledger, '${_head}2026-10-03,退款,1,銀行,,,,,,,r2,p,,\n');
    expect(again.problems, ['第 2 行：找不到可以退款的原支出']);
  });

  test('a 編號 the book has, or the file had, leaves the line out', () {
    final ledger = _book([
      entryOf('a1', day(2026, 10, 1), EntryType.expense, 1, 'bank'),
    ]);
    final found = _read(
      ledger,
      '$_head'
      '2026-10-05,支出,10,銀行,,飲食,,,,,a1,,,\n'
      '2026-10-05,支出,20,銀行,,飲食,,,,,b1,,,\n'
      '2026-10-05,支出,30,銀行,,飲食,,,,,b1,,,\n',
    );
    expect([for (final e in found.entries) e.amount], [20]);
    expect(found.problems, ['第 2 行：帳本裡已經有這一筆', '第 4 行：檔案裡已經有「編號」是 b1 的一筆']);
  });

  test('a 編號 of an entry in the trash is not reused', () {
    final ledger = _book([
      entryOf('t1', day(2026, 10, 1), EntryType.expense, 1, 'bank'),
    ]);
    ledger.entryCommands.remove('t1');
    final found = _read(ledger, '${_head}2026-10-05,支出,10,銀行,,飲食,,,,,t1,,,\n');
    expect(found.entries.single.id, isNot('t1'));
  });

  test('a recurring item the book does not have is no link', () {
    final found = _read(
      _book(),
      '${_head}2026-10-05,支出,10,銀行,,飲食,,,,,,,,gone\n',
    );
    expect(found.entries.single.recurring, isNull);
  });

  test('the mark (D52) and the day-trade flag (D6) are read', () {
    final ledger = _book();
    addImport(
      ledger.entryCommands,
      _read(ledger, '${_head}2026-10-01,買進,10000,銀行,,,,,2330,10,,,,\n'),
    );
    final found = _read(
      ledger,
      '$_head'
      '2026-10-02,收入,50,信用卡,,,回饋,,,,,,,\n'
      '2026-10-02,支出,1200,信用卡,,飲食,年費,,,,,,,\n'
      '2026-10-02,支出,80,銀行,,飲食,發票,,,,,,,\n'
      '2026-10-02,賣出,11000,銀行,,,,是,2330,10,,,,\n'
      '2026-10-03,支出,80,銀行,,飲食,紅利,,,,,,,\n'
      '2026-10-03,支出,80,銀行,,飲食,,也許,,,,,,\n',
    );
    expect(
      [for (final e in found.entries) e.mark],
      [EntryMark.reward, EntryMark.annualFee, EntryMark.invoice, null],
    );
    expect(found.entries.last.dayTrade, isTrue);
    expect(found.problems, ['第 6 行：不認得的「標記」「紅利」', '第 7 行：「當沖」看不懂，請填「是」或留空']);
  });

  test('the same book writes the same file: by day, a refund after its '
      'spending, else in the order of the book', () {
    final entries = [
      entryOf(
        'r',
        day(2026, 10, 2),
        EntryType.income,
        5,
        'bank',
        category: '飲食',
        refundOf: 'b',
      ),
      entryOf('b', day(2026, 10, 2), EntryType.expense, 9, 'bank'),
      entryOf('a', day(2026, 10, 1), EntryType.expense, 1, 'bank'),
      entryOf('c', day(2026, 10, 2), EntryType.expense, 3, 'bank'),
    ];
    expect([for (final e in exportOrder(entries)) e.id], ['a', 'b', 'c', 'r']);
    expect(
      [for (final e in exportOrder(entries.reversed)) e.id],
      ['a', 'c', 'b', 'r'],
    );
  });

  test('a file without 日期 names both required columns', () {
    final found = _read(_book(), '金額\n5\n');
    expect(found.problems, ['第一行要有「日期」和「金額」欄位']);
  });
}
