import 'package:core/constants/category_colors.dart';
import 'package:core/foundation_values.dart' show BusinessDate;
import 'package:core/fx/dated_figures.dart'
    show DatedFigures, FoundOn, MarketHistory;
import 'package:expense_tracker/src/core/messages/import_messages.dart'
    show importEstimatedWords;
import 'package:expense_tracker/src/app/demo/seed.dart';
import 'package:expense_tracker/src/features/import_export/model/import_export.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/src/features/import_export/ui/import_page.dart'
    show importBookOf;

import '../../../support/seeded_book.dart' show emptyBook;

void main() {
  test('a file with words after a closing quote is left out, naming the '
      'line', () {
    final result = importCsv(
      importBookOf(demoLedger()),
      '日期,金額\n2026-10-01,120\n2026-10-02,"12"3\n',
      fallback: 'cash',
    );
    expect(result.entries, isEmpty);
    expect(result.problems, ['第 3 行的引號看不懂，整個檔案沒有匯入']);
  });

  test('IMP-04: an amount that could be misread is that line\'s error, '
      'never a guess or an exception', () {
    final result = importCsv(
      importBookOf(demoLedger()),
      '日期,類型,金額\n'
      '2026-10-01,支出,.5\n'
      '2026-10-02,支出,99999999999999999999\n'
      '2026-10-03,支出,"1.234,50"\n'
      '2026-10-04,支出,12.345\n'
      '2026-10-05,支出,1 200\n'
      '2026-10-06,支出,"1,200"\n',
      fallback: 'cash',
    );
    // Only the well-written 1,200 is read; once 1.234,50 read as 1,
    // 12.345 as 12 and 1 200 as 1200, and .5 threw.
    expect(result.entries.map((e) => e.amount), [1200]);
    expect(result.problems, [
      '第 2 行：金額看不懂：不是有效的金額',
      '第 3 行：金額看不懂：金額不能超過 999,999,999',
      '第 4 行：金額看不懂：看不出是哪個數字，請寫成 1,234.50 這樣',
      '第 5 行：金額看不懂：看不出是哪個數字，請寫成 1,234.50 這樣',
      '第 6 行：金額看不懂：不是有效的金額',
    ]);
  });

  test('every amount column is read as strictly as 金額: a fee, a tax, '
      'what a transfer brings in and the NT\$ worth, each said by its '
      'column (review 16: CSV per column)', () {
    final result = importCsv(
      importBookOf(emptyBook()),
      '日期,類型,金額,帳戶,轉入帳戶,代號,股數,手續費,稅,轉入金額,台幣金額\n'
      '2026-10-01,轉帳,500,銀行,現金,,,.5,,,\n'
      '2026-10-02,轉帳,3200,銀行,美元戶,,,,,1 200,\n'
      '2026-10-03,買進,50000,銀行,,2330,100,1 200,,,\n'
      '2026-10-04,股息,1000,銀行,,2330,,,.5,,\n'
      '2026-10-05,支出,10,美元戶,,,,,,,.5\n'
      '2026-10-06,轉帳,500,銀行,現金,,,15,,,\n',
      fallback: 'cash',
    );
    // Only the last, with a fee of 15 written plainly, is read.
    expect(result.entries.map((e) => (e.amount, e.fee)), [(500, 15)]);
    expect(result.problems, [
      '第 2 行：手續費看不懂：不是有效的金額',
      '第 3 行：轉入金額看不懂：不是有效的金額',
      '第 4 行：手續費看不懂：不是有效的金額',
      '第 5 行：稅看不懂：不是有效的金額',
      '第 6 行：台幣金額看不懂：不是有效的金額',
    ]);
  });

  test('IMP-04: an e-invoice line with an odd total is left out, not '
      'thrown on', () {
    final result = importInvoices(
      importBookOf(demoLedger()),
      'M|手機條碼|/ABC123|20261003|12345678|甲店|AB00000001|.5|開立\n'
      'M|手機條碼|/ABC123|20261003|12345678|乙店|AB00000002|120|開立\n',
      account: 'cash',
    );
    expect(result.entries.map((e) => e.amount), [120]);
    expect(result.problems, ['AB00000001：金額看不懂']);
  });

  test('an exported month imports as nothing new', () {
    final ledger = demoLedger();
    final month = ledger.entries.inMonth(2026, 9);
    final csv = toCsv(ledger.accounts, month);
    final again = importCsv(importBookOf(ledger), csv, fallback: 'cash');
    expect(again.entries, isEmpty);
    expect(again.accounts, isEmpty);
    final fresh = importCsv(
      importBookOf(ledger),
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
    // The colour a category made in 記一筆 would take next (review 32):
    // the book's count of categories into the one list.
    expect(
      fresh.categories.single.color,
      nextCategoryColor(ledger.categories.all.length),
    );
    final before = ledger.reportService.expense(2026, 10);
    addImport(ledger.entryCommands, fresh);
    expect(ledger.account(made.id).name, '不存在的帳戶');
    expect(ledger.reportService.expense(2026, 10), before + 120);
  });

  test('every kind of entry imports, and reads back as nothing new', () {
    final ledger = demoLedger();
    // Dated before the book's today (10/4): a trade cannot be 預定 (D25).
    const text =
        '日期,類型,金額,帳戶,轉入帳戶,分類,商家,標籤,備註,代號,股數,手續費,稅,分期\n'
        '2026-09-01,支出,300,新信用卡,,餐飲=200;居家生活=100,好市多,,,,,,,3\n'
        '2026-09-02,轉帳,5000,日常銀行,新信用卡,,,,繳卡費\n'
        '2026-09-02,轉帳,1000,日常銀行,零錢包現金,,,,提款,,,15\n'
        '2026-09-03,買進,60000,日常銀行,,,,,,00713,1000,85\n'
        '2026-09-04,賣出,30000,日常銀行,,,,,,00713,500,42,90\n'
        '2026-09-05,股息,1200,日常銀行,,,,,,00713,,,25\n'
        '2026-09-06,配股,,日常銀行,,,,,,00713,50\n'
        '2026-09-07,退款,100,新信用卡,,,好市多,,退貨\n'
        '2026-09-08,賣出,1,日常銀行,,,,,,00713,999999\n'
        '2026-09-09,魔法,1,日常銀行\n';
    final found = importCsv(importBookOf(ledger), text, fallback: 'bank');
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

    addImport(ledger.entryCommands, found);
    expect(ledger.holding('00713')!.shares, 550);
    final again = importCsv(
      importBookOf(ledger),
      toCsv(ledger.accounts, found.entries),
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
    final found = importInvoices(importBookOf(ledger), text, account: 'card');
    expect(found.entries, hasLength(2));
    expect(found.skipped, 1);
    final first = found.entries.first;
    expect(first.merchant, '全聯福利中心');
    expect(first.amount, 268);
    expect(first.note, '鮮奶 等 2 項 發票 AB00000001');
    expect(found.entries.last.category, '交通通勤');
    ledger.entryCommands.addAll(found.entries);
    expect(
      importInvoices(importBookOf(ledger), text, account: 'card').entries,
      isEmpty,
    );
  });

  test('invoices are not recorded on a foreign-currency account', () {
    final ledger = demoLedger()
      ..accountCommands.addAccount(
        const Account('usd', '美元', AccountKind.bank, 0, currency: 'USD'),
      );
    const text = 'M|手機條碼|/ABC123|20261003|12345678|全聯福利中心|AB00000001|268|開立\n';
    final found = importInvoices(importBookOf(ledger), text, account: 'usd');
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
    final found = importInvoices(importBookOf(ledger), text, account: 'card');
    expect(found.entries, hasLength(1));
    final first = found.entries.single;
    expect((first.amount, first.merchant), (268, '全聯福利中心'));
    expect(first.note, '鮮奶 等 2 項 發票 CD00000001');
    ledger.entryCommands.addAll(found.entries);
    expect(
      importInvoices(importBookOf(ledger), text, account: 'card').entries,
      isEmpty,
    );
    expect(
      importInvoices(importBookOf(ledger), '發票號碼\n壞', account: 'card').skipped,
      1,
    );
  });

  test('a foreign account imports in its own currency', () {
    final ledger = demoLedger()
      ..accountCommands.addAccount(
        const Account('usd', '美元', AccountKind.bank, 0, currency: 'USD'),
      );
    final found = importCsv(
      importBookOf(ledger),
      '日期,類型,金額,帳戶,分類\n2026-10-01,支出,12.5,美元,飲食日常\n',
      fallback: 'bank',
    );
    final entry = found.entries.single;
    expect((entry.account, entry.amount), ('usd', 1250));
    expect(entry.home, (12.5 * 32.1).round());
    expect(toCsv(ledger.accounts, [entry]), contains(',12.50,美元,'));
  });

  test('R5/D123: a row worth at home at today\'s rate says it is an '
      'estimate, and why', () {
    final ledger = Ledger(
      today: DateTime.utc(2026, 11, 13),
      accounts: const [
        Account('bank', '銀行', AccountKind.bank, 0),
        Account('usd', '美元', AccountKind.bank, 0, currency: 'USD'),
      ],
      categories: [Category('飲食', 'food', 0xFF5C9A83)],
      entries: const [],
      holdings: const [],
      budgets: const [],
      recurring: const [],
      rates: const {'USD': 32.0},
      history: MarketHistory(
        buying: DatedFigures({
          'USD': {BusinessDate(2026, 9, 1): 30.0},
        }),
      ),
    );
    final found = importCsv(
      importBookOf(ledger),
      '日期,類型,金額,帳戶,分類\n'
      '2026-10-01,支出,10,美元,飲食\n'
      '2026-10-02,支出,10,美元,飲食\n'
      '2026-08-01,支出,10,美元,飲食\n'
      '2026-11-13,支出,10,美元,飲食\n',
      fallback: 'bank',
    );
    final byDay = {for (final e in found.entries) e.date.day: e};
    // 10/1: 9/1's board, 30 days before: US\$10 x 30 = 300, no note.
    expect(byDay[1]!.home, 300);
    expect(found.estimated[byDay[1]!.id], isNull);
    // 10/2: 9/1's is 31 days before, too old: today's 32, 320.
    expect(byDay[2]!.home, 320);
    expect(found.estimated[byDay[2]!.id], FoundOn.todayEarlierTooOld);
    expect(
      importEstimatedWords(FoundOn.todayEarlierTooOld),
      '最近的牌價早於當日 30 天以上，不採用；台幣金額以今日匯率估算',
    );
    // 8/1: before any board kept: today's, 320.
    expect(found.entries.firstWhere((e) => e.date.month == 8).home, 320);
    expect(
      found.estimated[found.entries.firstWhere((e) => e.date.month == 8).id],
      FoundOn.today,
    );
    expect(importEstimatedWords(FoundOn.today), '台幣金額以今日匯率估算');
    // Today: today's board, no estimate.
    expect(found.estimated[byDay[13]!.id], isNull);
    // Kept only for the entries chosen.
    final second = found.entries.indexOf(byDay[2]!);
    expect(found.only({second}).estimated, {
      byDay[2]!.id: FoundOn.todayEarlierTooOld,
    });
    expect(found.only(const {}).estimated, isEmpty);
  });

  test('stock dividends and splits grow every lot at its own cost', () {
    final ledger = demoLedger();
    final before = ledger.holding('2330')!;
    final lotsBefore = ledger.holdings.lotsOf('2330');
    ledger.entryCommands.add(
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
    expect(ledger.holdings.lotsOf('2330'), hasLength(lotsBefore.length));
    expect(
      ledger.holdings.lotsOf('2330').fold(0, (sum, l) => sum + l.cost),
      before.cost,
    );
    ledger.entryCommands.add(
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
    final lots = ledger.holdings.lotsOf('2330');
    expect(lots.fold(0, (sum, l) => sum + l.shares), split.shares);
  });

  test('search finds entries of every month, newest first', () {
    final ledger = demoLedger();
    final found = ledger.entryQueryService.search('全聯');
    expect(found.length, greaterThan(1));
    expect(found.map((e) => e.date.month).toSet().length, greaterThan(1));
    for (var i = 1; i < found.length; i++) {
      expect(found[i].date.isAfter(found[i - 1].date), isFalse);
    }
  });

  group('R12: outside files read strictly', () {
    Import csv(String text) =>
        importCsv(importBookOf(demoLedger()), text, fallback: 'cash');

    test('a quote never closed leaves the whole file out (F5)', () {
      final found = csv('日期,金額,備註\n2026-10-01,5,"沒有收尾\n2026-10-02,6,午餐\n');
      expect(found.entries, isEmpty);
      expect(found.problems, ['第 2 行的引號看不懂，整個檔案沒有匯入']);
    });

    test('a two-digit year is refused with why; three digits are ROC (F4)', () {
      final found = csv('日期,類型,金額\n26/10/01,支出,5\n115/10/1,支出,6\n');
      expect(found.problems, ['第 2 行：年份只有兩位數，請寫成西元四位數（例如 2026）或民國三位數（例如 115）']);
      // 115 + 1911 = 2026.
      expect(found.entries.single.date, DateTime.utc(2026, 10, 1));
    });

    test('a day before 1950 is refused (D93)', () {
      final found = csv('日期,類型,金額\n1949/12/31,支出,5\n');
      expect(found.entries, isEmpty);
      expect(found.problems, ['第 2 行：日期早於 1950 年']);
    });

    test('a line is named by the line of the file (blank lines and line '
        'breaks in notes counted)', () {
      final found = csv(
        '日期,類型,金額,備註\n'
        '\n'
        '2026-10-01,支出,5,"兩\n行"\n'
        '\n'
        'abc,支出,6,x\n',
      );
      expect(found.entries, hasLength(1));
      // Line 1 the header, 2 blank, 3 and 4 the note of two lines, 5
      // blank, 6 the unreadable day.
      expect(found.problems, ['第 6 行：日期看不懂']);
    });

    test('an M line dated 0261003 (ROC 26, 1937) is refused (F4)', () {
      final found = importInvoices(
        importBookOf(demoLedger()),
        'M|x|y|0261003|1|甲店|AB00000009|10|開立\n',
        account: 'cash',
      );
      expect(found.entries, isEmpty);
      expect(found.problems, ['AB00000009：日期早於 1950 年']);
    });

    test('invoice AB1 is not taken for AB12 already read', () {
      final found = importInvoices(
        importBookOf(demoLedger()),
        'M|x|y|20261003|1|乙|AB12|20|開立\n'
        'M|x|y|20261003|1|甲|AB1|10|開立\n'
        'M|x|y|20261003|1|甲|AB1|10|開立\n',
        account: 'cash',
      );
      expect(found.entries.map((e) => e.note), ['發票 AB12', '發票 AB1']);
      expect(found.problems, ['AB1：已經記過']);
    });

    test('the ministry file: a void row voids, rows that disagree are '
        'left out, named (F6)', () {
      final found = importInvoices(
        importBookOf(demoLedger()),
        '發票日期,發票號碼,賣方名稱,發票狀態,消費明細_品名,消費明細_金額\n'
        '20261003,AB00000001,甲店,開立,鮮奶,10\n'
        '20261003,AB00000001,甲店,作廢,吐司,20\n'
        '20261003,AB00000002,甲店,開立,鮮奶,10\n'
        '20261004,AB00000002,乙店,開立,吐司,20\n'
        '20261005,AB00000003,丙店,開立,茶,30\n',
        account: 'cash',
      );
      expect(found.entries.map((e) => e.amount), [30]);
      expect(found.skipped, 1);
      expect(found.problems, ['AB00000002：同一張發票的日期或商家前後不一致']);
    });
  });

  // Moved from test/perf/import_gate_test.dart: what it checks is not
  // timed, so it runs with the ordinary suite (and its coverage).
  test('apart and at once read the same', () async {
    const small = '日期,類型,金額,帳戶,分類\n2026-10-01,支出,5,現金,飲食\nbad,支出,5,現金,x\n';
    final apart = await importCsvApart(
      importBookOf(demoLedger()),
      small,
      fallback: 'cash',
    );
    final once = importCsv(importBookOf(demoLedger()), small, fallback: 'cash');
    expect(apart.entries.map((e) => (e.date, e.amount, e.category)), [
      (DateTime.utc(2026, 10, 1), 5, '飲食'),
    ]);
    expect(once.entries.map((e) => (e.date, e.amount, e.category)), [
      (DateTime.utc(2026, 10, 1), 5, '飲食'),
    ]);
    expect(apart.problems, ['第 3 行：日期看不懂']);
    expect(once.problems, apart.problems);
    final open = await importCsvApart(
      importBookOf(demoLedger()),
      '日期,金額\n2026-10-01,"5\n',
      fallback: 'cash',
    );
    expect(open.problems, ['第 2 行的引號看不懂，整個檔案沒有匯入']);
  });

  test('a file of readApartFrom characters or more is read as CSV on a '
      'worker, and reads the same', () async {
    expect(readApartFrom, 100000);
    // Each line '2026-10-01,支出,<1..9>,隨身現金,飲食,第 <i> 筆' is about 30
    // characters: 4,000 lines are over 100,000.
    final text = StringBuffer('日期,類型,金額,帳戶,分類,備註\n');
    for (var i = 0; i < 4000; i++) {
      text.write('2026-10-01,支出,${1 + i % 9},隨身現金,飲食,第 $i 筆\n');
    }
    final csv = text.toString();
    expect(csv.length, greaterThanOrEqualTo(100000));
    final apart = await importCsvApart(
      importBookOf(demoLedger()),
      csv,
      fallback: 'cash',
    );
    final once = importCsv(importBookOf(demoLedger()), csv, fallback: 'cash');
    expect(apart.entries, hasLength(4000));
    expect(apart.problems, isEmpty);
    expect(
      apart.entries.map((e) => (e.date, e.amount, e.note)),
      once.entries.map((e) => (e.date, e.amount, e.note)),
    );
  });
}
