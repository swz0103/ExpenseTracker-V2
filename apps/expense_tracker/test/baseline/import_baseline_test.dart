// CSV in and out: byte order mark, the formula-injection guard both ways,
// duplicate detection and the amounts and dates people type. Every expected
// string and number is written out, none taken from the code or demo data.
import 'package:domain/data_exchange.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/features/import_export/model/import_export.dart';
import 'package:expense_tracker/src/features/import_export/ui/import_page.dart'
    show importBookOf;
import 'package:flutter_test/flutter_test.dart';

import 'baseline_ledger.dart';

Ledger book([List<Entry> entries = const []]) => ledgerOf(
  today: day(2026, 10, 10),
  accounts: const [
    Account('bank', '銀行', AccountKind.bank, 0),
    Account('cash', '現金', AccountKind.cash, 0),
  ],
  categories: [Category('飲食', 'food', 0xFF5C9A83)],
  entries: entries,
);

Import read(Ledger ledger, String text) =>
    importCsv(importBookOf(ledger), text, fallback: 'bank');

void main() {
  group('byte order mark and line ends', () {
    test('a file starting with a BOM reads like one without', () {
      final plain = parseCsv('日期,備註\n2026-03-05,午餐\n');
      final bom = parseCsv('\u{FEFF}日期,備註\n2026-03-05,午餐\n');
      expect(bom, [
        ['日期', '備註'],
        ['2026-03-05', '午餐'],
      ]);
      expect(bom, plain);
    });
    test('the BOM does not spoil the first column name on import', () {
      final found = read(
        book(),
        '\u{FEFF}日期,類型,金額,帳戶,分類\n2026-10-01,支出,120,銀行,飲食\n',
      );
      expect(found.entries, hasLength(1));
      expect(found.entries.single.amount, 120);
      expect(found.skipped, 0);
    });
    test('CRLF and LF lines read the same', () {
      expect(parseCsv('a,b\r\n1,2\r\n'), [
        ['a', 'b'],
        ['1', '2'],
      ]);
      expect(parseCsv('a,b\n1,2\n'), parseCsv('a,b\r\n1,2\r\n'));
    });
    test('written files start with a BOM and end lines with CRLF', () {
      expect(
        writeCsv([
          ['a', 'b'],
        ]),
        '\u{FEFF}a,b\r\n',
      );
    });
  });

  group('formula-injection guard, writing', () {
    test('words a spreadsheet would run get a quote before them', () {
      expect(
        writeCsv([
          ['=SUM(A1)'],
        ]),
        "\u{FEFF}'=SUM(A1)\r\n",
      );
      expect(
        writeCsv([
          ['+cmd'],
        ]),
        "\u{FEFF}'+cmd\r\n",
      );
      expect(
        writeCsv([
          ['-x'],
        ]),
        "\u{FEFF}'-x\r\n",
      );
      expect(
        writeCsv([
          ['@sum'],
        ]),
        "\u{FEFF}'@sum\r\n",
      );
    });
    test('plain numbers, even negative ones, are left alone', () {
      expect(
        writeCsv([
          ['-5', '+3', '12.5'],
        ]),
        '\u{FEFF}-5,+3,12.5\r\n',
      );
    });
    test('a quote already there gets one more, so reading undoes it', () {
      expect(
        writeCsv([
          ["'=x"],
        ]),
        "\u{FEFF}''=x\r\n",
      );
    });
    test('commas and quotes are quoted RFC 4180 style', () {
      expect(
        writeCsv([
          ['a,b', 'say "hi"'],
        ]),
        '\u{FEFF}"a,b","say ""hi"""\r\n',
      );
    });
  });

  group('formula-injection guard, reading', () {
    test('the guard quote is taken off again', () {
      expect(parseCsv("'=SUM(A1)\n"), [
        ['=SUM(A1)'],
      ]);
      expect(parseCsv("''=x\n"), [
        ["'=x"],
      ]);
    });
    test('an ordinary leading quote is kept as written', () {
      expect(parseCsv("'hello\n"), [
        ["'hello"],
      ]);
    });
    test('a note starting with = survives an export and import', () {
      final ledger = book([
        entryOf(
          'e',
          day(2026, 10, 1),
          EntryType.expense,
          100,
          'bank',
          category: '飲食',
          note: '=1+1',
        ),
      ]);
      final csv = toCsv(ledger.accounts, ledger.entries.all);
      // The file holds the guarded words, not a live formula.
      expect(csv, contains(",'=1+1,"));
      final other = book();
      final found = read(other, csv);
      expect(found.entries.single.note, '=1+1');
    });
  });

  group('what is read from a line', () {
    test('amounts with thousands commas or NT\$ are read as written', () {
      final found = read(
        book(),
        '日期,類型,金額,帳戶,分類\n'
        '2026-10-01,支出,"1,200",銀行,飲食\n'
        '2026-10-02,支出,NT\$ 85,銀行,飲食\n',
      );
      expect(found.entries.map((e) => e.amount), [1200, 85]);
    });
    test('without a type a negative amount is spending of its size', () {
      final found = read(book(), '日期,金額,帳戶,分類\n2026-10-01,-50,銀行,飲食\n');
      expect(found.entries.single.type, EntryType.expense);
      expect(found.entries.single.amount, 50);
    });
    test('the type names 支出, 收入 and 轉帳 are read', () {
      final found = read(
        book(),
        '日期,類型,金額,帳戶,轉入帳戶,分類\n'
        '2026-10-01,支出,10,銀行,,飲食\n'
        '2026-10-02,收入,20,銀行,,飲食\n'
        '2026-10-03,轉帳,30,銀行,現金,\n',
      );
      expect(found.entries.map((e) => e.type), [
        EntryType.expense,
        EntryType.income,
        EntryType.transfer,
      ]);
      expect(found.entries.last.to, 'cash');
    });
    test('a line with no account goes to the fallback account', () {
      final found = read(book(), '日期,類型,金額\n2026-10-01,支出,10\n');
      expect(found.entries.single.account, 'bank');
    });
    test('dates: dashes, slashes, packed and Republic of China years', () {
      expect(readDay('2026-03-05'), day(2026, 3, 5));
      expect(readDay('2026/3/5'), day(2026, 3, 5));
      expect(readDay('20260305'), day(2026, 3, 5));
      // ROC year 115 is 2026 (115 + 1911).
      expect(readDay('1150305'), day(2026, 3, 5));
      expect(readDay('115/3/5'), day(2026, 3, 5));
    });
    test('impossible dates are not read', () {
      expect(readDay('2026-02-30'), isNull);
      expect(readDay('2026-13-01'), isNull);
      expect(readDay('2026-00-10'), isNull);
      expect(readDay('abc'), isNull);
    });
    test('leap day exists only in leap years', () {
      expect(readDay('2028-02-29'), day(2028, 2, 29));
      expect(readDay('2026-02-29'), isNull);
    });
  });

  group('lines that are left out', () {
    test('a file without date and amount columns is refused', () {
      final found = read(book(), '備註\n午餐\n');
      expect(found.entries, isEmpty);
      expect(found.problems, ['第一行要有「日期」和「金額」欄位']);
    });
    test('an unreadable line is skipped and says which line', () {
      final found = read(
        book(),
        '日期,類型,金額,帳戶,分類\n'
        '2026-10-01,支出,10,銀行,飲食\n'
        '壞掉的一行\n'
        '2026-10-03,支出,30,銀行,飲食\n',
      );
      expect(found.entries.map((e) => e.amount), [10, 30]);
      expect(found.skipped, 1);
      expect(found.problems.single, startsWith('第 3 行：'));
    });
    test('an unknown type is skipped', () {
      final found = read(book(), '日期,類型,金額,帳戶\n2026-10-01,魔法,10,銀行\n');
      expect(found.entries, isEmpty);
      expect(found.skipped, 1);
      expect(found.problems.single, contains('魔法'));
    });
    test('words after a closing quote refuse the whole file', () {
      final found = read(book(), '日期,金額\n2026-10-01,120\n2026-10-02,"12"3\n');
      expect(found.entries, isEmpty);
      expect(found.problems, ['第 3 行的引號看不懂，整個檔案沒有匯入']);
    });
    test('an unclosed quote is read to the end', () {
      expect(parseCsv('日期,備註\n2026-03-05,"沒有收尾'), [
        ['日期', '備註'],
        ['2026-03-05', '沒有收尾'],
      ]);
    });
    test('a sale of shares not held is left out, with the reason', () {
      final found = read(
        book(),
        '日期,類型,金額,帳戶,代號,股數\n2026-10-08,賣出,100,銀行,2330,5\n',
      );
      expect(found.entries, isEmpty);
      expect(found.skipped, 1);
    });
  });

  group('duplicates', () {
    const line = '2026-10-01,支出,120,銀行,飲食,早餐店,,蛋餅\n';
    const head = '日期,類型,金額,帳戶,分類,商家,標籤,備註\n';
    test('a line already in the book is left out', () {
      final ledger = book();
      final first = read(ledger, '$head$line');
      expect(first.entries, hasLength(1));
      addImport(ledger.entryCommands, first);
      final again = read(ledger, '$head$line');
      expect(again.entries, isEmpty);
      expect(again.skipped, 1);
    });
    test('same day, type, amount, account and note count as the same', () {
      final ledger = book([
        entryOf(
          'x',
          day(2026, 10, 1),
          EntryType.expense,
          120,
          'bank',
          category: '飲食',
          note: '蛋餅',
        ),
      ]);
      expect(read(ledger, '$head$line').entries, isEmpty);
    });
    test('another amount, day or note is not a duplicate', () {
      final ledger = book([
        entryOf(
          'x',
          day(2026, 10, 1),
          EntryType.expense,
          120,
          'bank',
          category: '飲食',
          note: '蛋餅',
        ),
      ]);
      expect(
        read(ledger, '${head}2026-10-01,支出,121,銀行,飲食,早餐店,,蛋餅\n').entries,
        hasLength(1),
      );
      expect(
        read(ledger, '${head}2026-10-02,支出,120,銀行,飲食,早餐店,,蛋餅\n').entries,
        hasLength(1),
      );
      expect(
        read(ledger, '${head}2026-10-01,支出,120,銀行,飲食,早餐店,,漢堡\n').entries,
        hasLength(1),
      );
    });
    test('an export of the book imports as nothing new', () {
      final ledger = book([
        entryOf(
          'x',
          day(2026, 10, 1),
          EntryType.expense,
          120,
          'bank',
          category: '飲食',
          merchant: '早餐店',
          note: '蛋餅',
        ),
        entryOf(
          'y',
          day(2026, 10, 2),
          EntryType.transfer,
          500,
          'bank',
          to: 'cash',
          fee: 15,
        ),
      ]);
      final csv = toCsv(ledger.accounts, ledger.entries.all);
      final found = read(ledger, csv);
      expect(found.entries, isEmpty);
      expect(found.accounts, isEmpty);
    });
  });

  group('what an export looks like', () {
    test('the header names the columns in a fixed order', () {
      final csv = toCsv(book().accounts, const []);
      expect(
        csv,
        '\u{FEFF}日期,類型,金額,帳戶,轉入帳戶,分類,商家,標籤,備註,代號,股數,'
        '手續費,稅,分期,轉入金額,台幣金額,成本算法,當沖,標記,編號,退款對象,群組,定期\r\n',
      );
    });
    test('an expense with merchant, tags and note is one line', () {
      final ledger = book([
        entryOf(
          'x',
          day(2026, 3, 5),
          EntryType.expense,
          120,
          'bank',
          category: '飲食',
          merchant: '早餐店',
          tags: const ['家用', '早餐'],
          note: '蛋餅',
        ),
      ]);
      final lines = toCsv(ledger.accounts, ledger.entries.all).split('\r\n');
      expect(lines[1], '2026-03-05,支出,120,銀行,,飲食,早餐店,家用、早餐,蛋餅,,,,,,,,,,,x,,,');
    });
    test('a split is written as name=amount parts', () {
      final ledger = book([
        entryOf(
          'x',
          day(2026, 3, 5),
          EntryType.expense,
          300,
          'bank',
          category: '飲食',
          parts: const [('飲食', 200), ('居家', 100)],
        ),
      ]);
      final lines = toCsv(ledger.accounts, ledger.entries.all).split('\r\n');
      expect(lines[1], '2026-03-05,支出,300,銀行,,飲食=200;居家=100,,,,,,,,,,,,,,x,,,');
    });
    test('a transfer carries its fee and receiving account', () {
      final ledger = book([
        entryOf(
          'x',
          day(2026, 3, 5),
          EntryType.transfer,
          500,
          'bank',
          to: 'cash',
          fee: 15,
        ),
      ]);
      final lines = toCsv(ledger.accounts, ledger.entries.all).split('\r\n');
      expect(lines[1], '2026-03-05,轉帳,500,銀行,現金,,,,,,,15,,,,,,,,x,,,');
    });
    test('lines are written oldest first', () {
      final ledger = book([
        entryOf('b', day(2026, 3, 6), EntryType.expense, 2, 'bank'),
        entryOf('a', day(2026, 3, 5), EntryType.expense, 1, 'bank'),
      ]);
      final lines = toCsv(ledger.accounts, ledger.entries.all).split('\r\n');
      expect(lines[1], startsWith('2026-03-05,'));
      expect(lines[2], startsWith('2026-03-06,'));
    });
  });
}
