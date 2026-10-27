import 'package:domain/data_exchange.dart';
import 'package:expense_tracker/src/app/demo/seed.dart';
import 'package:expense_tracker/src/features/import/model/exchange.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('CSV fields are quoted and read back', () {
    final fields = ['午餐', 'a,b', '說"好"', '兩\n行'];
    expect(parseCsv(writeCsv([fields])), [fields]);
    final rows = parseCsv('\u{FEFF}日期,備註\r\n2026-03-05,"a,b ""c"""\n\n');
    expect(rows, [
      ['日期', '備註'],
      ['2026-03-05', 'a,b "c"'],
    ]);
    expect(parseCsv('日期,備註\n2026-03-05,"沒有收尾'), [
      ['日期', '備註'],
      ['2026-03-05', '沒有收尾'],
    ]);
    expect(readDay('2026/3/5'), DateTime.utc(2026, 3, 5));
    expect(readDay('20260305'), DateTime.utc(2026, 3, 5));
    expect(readDay('1150305'), DateTime.utc(2026, 3, 5));
    expect(readDay('2026-02-30'), isNull);
  });

  test('an exported month imports as nothing new', () {
    final ledger = demoLedger();
    final month = ledger.entriesIn(2026, 9);
    final csv = toCsv(ledger, month);
    final again = importCsv(ledger, csv, fallback: 'cash');
    expect(again.entries, isEmpty);
    expect(again.accounts, isEmpty);
    final fresh = importCsv(
      ledger,
      '日期,類型,金額,帳戶,分類,商家,標籤,備註\n'
      '2026-10-01,支出,120,隨身現金,飲食日常,早餐店,家用,蛋餅\n'
      '2026-10-01,收入,500,不存在的帳戶,不存在,,,紅包\n'
      '壞掉的一行\n',
      fallback: 'bank',
    );
    expect(fresh.entries, hasLength(2));
    expect(fresh.skipped, 1);
    expect(fresh.entries.first.merchant, '早餐店');
    expect(fresh.entries.first.tags, ['家用']);
    expect(fresh.problems.single, startsWith('第 4 行：'));
    // A new account and category are added, not filed elsewhere.
    final made = fresh.accounts.single;
    expect((made.name, made.kind), ('不存在的帳戶', AccountKind.bank));
    expect(fresh.entries.last.account, made.id);
    expect(fresh.entries.last.category, '不存在');
    expect(fresh.categories.single.income, isTrue);
    final before = ledger.expense(2026, 10);
    addImport(ledger, fresh);
    expect(ledger.account(made.id).name, '不存在的帳戶');
    expect(ledger.expense(2026, 10), before + 120);
  });

  test('every kind of entry imports, and reads back as nothing new', () {
    final ledger = demoLedger();
    const text =
        '日期,類型,金額,帳戶,轉入帳戶,分類,商家,標籤,備註,代號,股數,手續費,稅,分期\n'
        '2026-10-01,支出,300,新信用卡,,餐飲=200;居家生活=100,好市多,,,,,,,3\n'
        '2026-10-02,轉帳,5000,日常銀行,新信用卡,,,,繳卡費\n'
        '2026-10-02,轉帳,1000,日常銀行,零錢包現金,,,,提款,,,15\n'
        '2026-10-03,買進,60000,日常銀行,,,,,,00713,1000,85\n'
        '2026-10-04,賣出,30000,日常銀行,,,,,,00713,500,42,90\n'
        '2026-10-05,股息,1200,日常銀行,,,,,,00713,,,25\n'
        '2026-10-06,配股,,日常銀行,,,,,,00713,50\n'
        '2026-10-07,退款,100,新信用卡,,,好市多,,退貨\n'
        '2026-10-08,賣出,1,日常銀行,,,,,,00713,999999\n'
        '2026-10-09,魔法,1,日常銀行\n';
    final found = importCsv(ledger, text, fallback: 'bank');
    expect(found.entries.map((e) => e.type), [
      EntryType.expense,
      EntryType.transfer,
      EntryType.transfer,
      EntryType.buy,
      EntryType.sell,
      EntryType.dividend,
      EntryType.dividend,
      EntryType.income,
    ]);
    expect(found.skipped, 2);
    expect(found.problems, hasLength(2));
    expect(found.problems.first, contains('魔法'));
    expect(found.problems.last, contains('超過'));
    final [card, cash] = found.accounts;
    expect((card.name, card.kind), ('新信用卡', AccountKind.card));
    expect((cash.name, cash.kind), ('零錢包現金', AccountKind.cash));
    expect(found.categories.map((c) => c.name), ['餐飲']);
    final spent = found.entries.first;
    expect(spent.parts, [('餐飲', 200), ('居家生活', 100)]);
    expect((spent.account, spent.installments), (card.id, 3));
    expect(found.entries[1].to, card.id);
    expect(found.entries[2].fee, 15);
    expect((found.entries[4].fee, found.entries[4].tax), (42, 90));
    expect(found.entries[5].tax, 25);
    expect(found.entries[6].shares, 50);
    expect(found.entries.last.refundOf, spent.id);

    addImport(ledger, found);
    expect(ledger.holding('00713')!.shares, 550);
    final again = importCsv(
      ledger,
      toCsv(ledger, found.entries),
      fallback: 'bank',
    );
    expect(again.entries, isEmpty);
    expect(again.accounts, isEmpty);
  });

  test('e-invoices become spending at the shop, once', () {
    final ledger = demoLedger();
    const text =
        'M|手機條碼|/ABC123|20261003|12345678|全聯福利中心|AB00000001|268|開立\n'
        'D|AB00000001|199|鮮奶\n'
        'D|AB00000001|69|吐司\n'
        'M|手機條碼|/ABC123|20261004|87654321|中油加油站|AB00000002|900|開立\n'
        'M|手機條碼|/ABC123|20261004|87654321|某店|AB00000003|50|作廢\n';
    final found = importInvoices(ledger, text, account: 'card');
    expect(found.entries, hasLength(2));
    expect(found.skipped, 1);
    final first = found.entries.first;
    expect(first.merchant, '全聯福利中心');
    expect(first.amount, 268);
    expect(first.note, '鮮奶 等 2 項 發票 AB00000001');
    expect(found.entries.last.category, '交通通勤');
    ledger.addAll(found.entries);
    expect(importInvoices(ledger, text, account: 'card').entries, isEmpty);
  });

  test('invoices are not recorded on a foreign-currency account', () {
    final ledger = demoLedger()
      ..addAccount(
        const Account('usd', '美元', AccountKind.bank, 0, currency: 'USD'),
      );
    const text = 'M|手機條碼|/ABC123|20261003|12345678|全聯福利中心|AB00000001|268|開立\n';
    final found = importInvoices(ledger, text, account: 'usd');
    expect(found.entries, isEmpty);
    expect(found.skipped, 1);
    expect(found.problems, isNotEmpty);
  });

  test("the ministry's invoice CSV adds up each invoice's items", () {
    final ledger = demoLedger();
    const text =
        '發票日期,發票號碼,賣方名稱,發票狀態,消費明細_品名,消費明細_金額\n'
        '20261003,CD00000001,全聯福利中心,開立,鮮奶,199\n'
        '20261003,CD00000001,全聯福利中心,開立,吐司,69\n'
        '20261004,CD00000002,某店,作廢,飲料,50\n';
    final found = importInvoices(ledger, text, account: 'card');
    expect(found.entries, hasLength(1));
    final first = found.entries.single;
    expect((first.amount, first.merchant), (268, '全聯福利中心'));
    expect(first.note, '鮮奶 等 2 項 發票 CD00000001');
    ledger.addAll(found.entries);
    expect(importInvoices(ledger, text, account: 'card').entries, isEmpty);
    expect(importInvoices(ledger, '發票號碼\n壞', account: 'card').skipped, 1);
  });

  test('a foreign account imports in its own currency', () {
    final ledger = demoLedger()
      ..addAccount(
        const Account('usd', '美元', AccountKind.bank, 0, currency: 'USD'),
      );
    final found = importCsv(
      ledger,
      '日期,類型,金額,帳戶,分類\n2026-10-01,支出,12.5,美元,飲食日常\n',
      fallback: 'bank',
    );
    final entry = found.entries.single;
    expect((entry.account, entry.amount), ('usd', 1250));
    expect(entry.home, (12.5 * 32.1).round());
    expect(toCsv(ledger, [entry]), contains(',12.50,美元,'));
  });

  test('stock dividends and splits grow every lot at its own cost', () {
    final ledger = demoLedger();
    final before = ledger.holding('2330')!;
    final lotsBefore = ledger.lotsOf('2330');
    ledger.add(
      Entry(
        id: 'stock',
        date: ledger.today,
        type: EntryType.dividend,
        amount: 0,
        account: 'bank',
        holding: '2330',
        shares: 10,
      ),
    );
    final after = ledger.holding('2330')!;
    expect(after.shares, before.shares + 10);
    expect(after.cost, before.cost);
    // As the ledger records it: each lot grows, none is added at no cost.
    expect(ledger.lotsOf('2330'), hasLength(lotsBefore.length));
    expect(
      ledger.lotsOf('2330').fold(0, (sum, l) => sum + l.cost),
      before.cost,
    );
    ledger.add(
      Entry(
        id: 'split',
        date: ledger.today,
        type: EntryType.dividend,
        amount: 0,
        account: 'bank',
        holding: '2330',
        shares: after.shares,
        split: true,
      ),
    );
    final split = ledger.holding('2330')!;
    expect(split.shares, after.shares * 2);
    expect(split.cost, after.cost);
    expect(split.price, closeTo(after.price / 2, 0.001));
    final lots = ledger.lotsOf('2330');
    expect(lots.fold(0, (sum, l) => sum + l.shares), split.shares);
  });

  test('search finds entries of every month, newest first', () {
    final ledger = demoLedger();
    final found = ledger.search('全聯');
    expect(found.length, greaterThan(1));
    expect(found.map((e) => e.date.month).toSet().length, greaterThan(1));
    for (var i = 1; i < found.length; i++) {
      expect(found[i].date.isAfter(found[i - 1].date), isFalse);
    }
  });
}
