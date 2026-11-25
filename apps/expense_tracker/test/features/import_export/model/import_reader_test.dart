import 'dart:io';
import 'dart:math';

import 'package:core/foundation_values.dart' show BusinessDate;
import 'package:domain/data_exchange.dart';
import 'package:core/fx/dated_figures.dart' show DatedFigures, MarketHistory;
import 'package:expense_tracker/src/app/demo/seed.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/ledger/persistence/codec/record_shape.dart';
import 'package:expense_tracker/src/core/ledger/repositories/holding_repository.dart';
import 'package:expense_tracker/src/features/import_export/model/import_export.dart';
import 'package:expense_tracker/src/features/import_export/ui/import_page.dart'
    show importBookOf;
import 'package:flutter_test/flutter_test.dart';

import '../../../baseline/baseline_ledger.dart';

/// R12: CSV files made at random and mutated from the demo book's export
/// (seeded), imported. Importing never throws; every line is imported or
/// left out with why; what is imported is of a shape the book keeps, from
/// 1950 on, with no control characters or invisible marks in its words;
/// adding it never throws, and importing it again adds nothing. A few
/// hundred cases here; `FUZZ_CASES=4000` for a nightly run.
void main() {
  final cases = int.tryParse(Platform.environment['FUZZ_CASES'] ?? '') ?? 200;
  const fragments = [
    ',', ',', '"', '""', '\n', '\r\n', "'", '=', '-', '\t', ' ', '\u0000', //
    '​', '‏', '😀', '日期', '金額', '類型', '帳戶', '分類', '備註',
    '支出', '收入', '轉帳', '買進', '賣出', '退款', '2026-10-01', '26/10/01',
    '1150305', '0261003', '2026-02-30', '120', '1,200', '-5', '0',
    '99999999999999999999', '1.5', '現金', '現金​', '信用卡', '飲食日常',
    '2330', '1000', 'NaN',
  ];
  final unseen = RegExp(
    '[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F-\u009F​‌'
    '‎‏⁠﻿]',
  );

  String junk(Random r, int most) => [
    for (var i = 0, n = r.nextInt(most); i < n; i++)
      fragments[r.nextInt(fragments.length)],
  ].join();

  String mutate(Random r, String text) {
    var t = text;
    for (var k = 1 + r.nextInt(5); k > 0; k--) {
      final at = t.isEmpty ? 0 : r.nextInt(t.length);
      t = switch (r.nextInt(4)) {
        0 =>
          t.substring(0, at) +
              fragments[r.nextInt(fragments.length)] +
              t.substring(at),
        1 when t.isNotEmpty => t.substring(0, at) + t.substring(at + 1),
        2 => t.substring(0, at),
        _ =>
          t.substring(0, at) +
              String.fromCharCode(r.nextInt(0x3100)) +
              t.substring(at),
      };
    }
    return t;
  }

  final demo = demoLedger();
  final exported = toCsv(demo.accounts, demo.entries.all);
  const header = '日期,類型,金額,帳戶,轉入帳戶,分類,商家,標籤,備註,代號,股數,手續費,稅,分期,轉入金額';

  test('$cases files: imported or left out with why, never thrown', () {
    final r = Random(2025);
    for (var i = 0; i < cases; i++) {
      final text = switch (i % 3) {
        0 => mutate(r, exported),
        1 => '$header\n${junk(r, 40)}',
        _ => junk(r, 60),
      };
      final ledger = demoLedger();
      final found = importCsv(importBookOf(ledger), text, fallback: 'bank');
      final accounts = {
        for (final a in ledger.accounts.all) a.id,
        for (final a in found.accounts) a.id,
      };
      for (final e in found.entries) {
        final why = 'case $i: ${e.note}';
        expect(shapeIssues(e), isEmpty, reason: why);
        expect(accounts, contains(e.account), reason: why);
        expect(e.date.isUtc && e.date.hour == 0, isTrue, reason: why);
        expect(e.date.year, greaterThanOrEqualTo(earliestImportYear));
        for (final words in [e.note, e.merchant, e.category, ...e.tags]) {
          expect(unseen.hasMatch(words), isFalse, reason: why);
        }
      }
      List<CsvRecord>? records;
      try {
        records = readCsvRecords(text);
      } on CsvFormatException {
        records = null;
      }
      final head = records == null || records.isEmpty
          ? const <String>[]
          : records.first.cells;
      if (records != null && head.contains('日期') && head.contains('金額')) {
        // Every line is imported or left out, and each left out says why.
        expect(
          found.entries.length + found.skipped,
          records.length - 1,
          reason: 'case $i',
        );
        expect(found.problems, hasLength(found.skipped), reason: 'case $i');
      }
      addImport(ledger.entryCommands, found);
      final again = importCsv(importBookOf(ledger), text, fallback: 'bank');
      if (found.entries.isNotEmpty) {
        expect(
          again.entries.length,
          lessThan(found.entries.length),
          reason: 'case $i: imported twice',
        );
      }
    }
  }, timeout: const Timeout(Duration(minutes: 10)));

  test('control characters and invisible marks are taken out (R12)', () {
    final ledger = demoLedger();
    final before = ledger.accounts.all.length;
    final cash = ledger.accounts.all.firstWhere((a) => a.name == '隨身現金');
    final found = importCsv(
      importBookOf(ledger),
      '日期,類型,金額,帳戶,分類,商家,備註\n'
      '2026-10-01,支出,5,隨身現金​,飲食日常​,全聯\u0000,午\u0000餐‏\n',
      fallback: 'bank',
    );
    final e = found.entries.single;
    expect(e.account, cash.id);
    expect(e.category, '飲食日常');
    expect(e.merchant, '全聯');
    expect(e.note, '午餐');
    expect(found.accounts, isEmpty);
    expect(found.categories, isEmpty);
    expect(ledger.accounts.all, hasLength(before));
  });

  test('a transfer with its 編號 dated beyond the limit, as the settlement '
      'before archiving, is refused saying it is not brought back so '
      '(review 38 1)', () {
    final found = importCsv(
      importBookOf(demoLedger()),
      // Exception to glossary: the file format's columns.
      '日期,類型,金額,帳戶,轉入帳戶,編號\n'
      '2027-11-08,轉帳,5000,隨身現金,銀行,back\n'
      '2027-11-08,轉帳,5000,隨身現金,銀行,\n'
      '2027-11-08,支出,5000,隨身現金,,e1\n',
      fallback: 'bank',
    );
    // The demo book's today 2026-10-04 + 365 days = 2027-10-04.
    expect(found.problems, [
      '第 2 行：日期晚於 2027/10/4，最多只能排到 365 天後；這類轉帳（例如封存前的結清）不能用匯入帶回',
      '第 3 行：日期晚於 2027/10/4，最多只能排到 365 天後',
      '第 4 行：日期晚於 2027/10/4，最多只能排到 365 天後',
    ]);
    expect(found.entries, isEmpty);
  });

  group('a refund on a foreign account (r13 F2)', () {
    // Exception to glossary: the file format's column, kept so files written before read back.
    const head = '日期,類型,金額,帳戶,商家,台幣金額\n';
    const bought = '2026-09-01,支出,100,美元戶,Shop,3210\n';

    Import read(String rows, {String currency = 'USD'}) {
      final ledger = demoLedger();
      ledger.accountCommands.addAccount(
        Account('usd', '美元戶', AccountKind.bank, 1000000, currency: currency),
      );
      return importCsv(importBookOf(ledger), head + rows, fallback: 'bank');
    }

    test('its worth at home is the 台幣金額 written', () {
      final found = read('${bought}2026-09-02,退款,100,美元戶,Shop,3210\n');
      expect(found.problems, isEmpty);
      final refund = found.entries.last;
      expect(refund.refundOf, found.entries.first.id);
      expect(refund.home, 3210);
    });

    test('without one, its share of the purchase\'s worth (D62)', () {
      final found = read('${bought}2026-09-02,退款,40,美元戶,Shop,\n');
      expect(found.problems, isEmpty);
      // 3,210 x 40 / 100 = 1,284.
      expect(found.entries.last.home, 1284);
    });

    test('more than the purchase\'s worth left is refused, named', () {
      final found = read(
        '${bought}2026-09-02,退款,50,美元戶,Shop,1000\n'
        '2026-09-03,退款,50,美元戶,Shop,2300\n'
        '2026-09-04,退款,10,美元戶,Shop,-5\n',
      );
      // 3,210 - 1,000 = 2,210 of the worth left: 2,300 is over it. The
      // last asks for a worth below zero.
      expect(found.problems, [
        '第 4 行：「台幣金額」超過原支出還可退的 2,210',
        '第 5 行：「台幣金額」要大於 0',
      ]);
    });

    test('a day later than an entry may be dated is refused (r13 F6)', () {
      // ROC 999/1/1 is the year 2910.
      final found = read('999/1/1,支出,100,美元戶,Shop,3210\n');
      // The demo book's today 2026-10-04 + 365 days = 2027-10-04.
      expect(found.problems, ['第 2 行：日期晚於 2027/10/4，最多只能排到 365 天後']);
    });

    test('with no rate and no worth written, the column is named', () {
      final found = read('2026-09-01,支出,100,美元戶,Shop,\n', currency: 'GBP');
      expect(found.problems, ['第 2 行：還沒有匯率，請在「台幣金額」欄填折合新台幣的金額']);
    });
  });

  test('D58: a foreign row without 台幣金額 takes the rate of its day', () {
    final ledger = demoLedger();
    ledger.accountCommands.addAccount(
      const Account('usd', '美元戶', AccountKind.bank, 0, currency: 'USD'),
    );
    ledger.holdingCommands.setMarket(
      holdings: (ledger.holdings as HoldingRepository).start,
      moves: const {},
      rates: const {'USD': 32.0},
      history: MarketHistory(
        buying: DatedFigures({
          'USD': {BusinessDate(2026, 9, 1): 30.0},
        }),
      ),
    );
    final found = importCsv(
      importBookOf(ledger),
      '日期,類型,金額,帳戶,商家\n'
      '2026-09-03,支出,100,美元戶,Shop\n'
      '2026-08-03,支出,100,美元戶,Shop\n',
      fallback: 'bank',
    );
    expect(found.problems, isEmpty);
    // 9/3: 9/1's board, 100 x 30 = 3,000; 8/3, before any board kept:
    // today's, 100 x 32 = 3,200.
    expect(
      {for (final e in found.entries) e.date.month: e.home},
      {9: 3000, 8: 3200},
    );
  });

  group('a refund naming its spending (review 37 1)', () {
    Ledger book([List<Entry> entries = const []]) => ledgerOf(
      today: day(2026, 10, 20),
      accounts: const [
        Account('bank', '銀行', AccountKind.bank, 0),
        Account('cash', '現金', AccountKind.cash, 0),
        Account('usd', '美元帳戶', AccountKind.bank, 0, currency: 'USD'),
        Account('usd2', '美元現鈔', AccountKind.cash, 0, currency: 'USD'),
        Account('card', '信用卡', AccountKind.card, 0, closingDay: 20, dueDay: 5),
      ],
      categories: [Category('飲食', 'food', 0xFF111111)],
      entries: entries,
    );
    // Exception to glossary: the file format's columns.
    const head = '日期,類型,金額,帳戶,分類,編號,退款對象,台幣金額\n';
    const bought = '2026-10-01,支出,1000,銀行,飲食,s1,,\n';
    Import read(Ledger ledger, String rows) =>
        importCsv(importBookOf(ledger), head + rows, fallback: 'bank');

    test('of the file, in another currency, is refused naming 退款對象', () {
      // US$5 (500 cents) against a NT$1,000 purchase: not weighed as
      // 500 of 1,000.
      final found = read(book(), '${bought}2026-10-02,退款,5,美元帳戶,,r1,s1,150\n');
      expect(found.problems, ['第 3 行：「退款對象」s1：退款要退回和原支出同一種幣別的帳戶']);
      expect([for (final e in found.entries) e.id], ['s1']);
    });

    test('of the book, in another currency, is refused naming 退款對象', () {
      final ledger = book([
        entryOf(
          'p',
          day(2026, 10, 1),
          EntryType.expense,
          1000,
          'bank',
          category: '飲食',
        ),
      ]);
      final found = read(ledger, '2026-10-02,退款,5,美元帳戶,,r1,p,150\n');
      expect(found.problems, ['第 2 行：「退款對象」p：退款要退回和原支出同一種幣別的帳戶']);
      expect(found.entries, isEmpty);
    });

    test('of foreign spending, back in NT\$, is refused', () {
      final found = read(
        book(),
        '2026-10-01,支出,10,美元帳戶,飲食,u1,,321\n'
        '2026-10-02,退款,500,銀行,,r1,u1,\n',
      );
      expect(found.problems, ['第 3 行：「退款對象」u1：退款要退回和原支出同一種幣別的帳戶']);
    });

    test('of foreign spending, to another account of its currency, is kept '
        'with its share of the worth', () {
      final found = read(
        book(),
        '2026-10-01,支出,10,美元帳戶,飲食,u1,,321\n'
        '2026-10-02,退款,4,美元現鈔,,r1,u1,\n',
      );
      expect(found.problems, isEmpty);
      final refund = found.entries.last;
      expect(refund.account, 'usd2');
      expect(refund.refundOf, 'u1');
      // 321 x 400 / 1,000 = 128.4, rounded to 128.
      expect(refund.home, 128);
    });

    test('of card spending, to another account, is refused', () {
      final found = read(
        book(),
        '2026-10-01,支出,1000,信用卡,飲食,c1,,\n'
        '2026-10-02,退款,500,現金,,r1,c1,\n',
      );
      expect(found.problems, ['第 3 行：「退款對象」c1：信用卡消費的退款要退回同一張卡']);
    });

    test('of bank spending, to cash, is kept, as the composer offers', () {
      final found = read(book(), '${bought}2026-10-02,退款,500,現金,,r1,s1,\n');
      expect(found.problems, isEmpty);
      expect(found.entries.last.refundOf, 's1');
    });

    test('more than is left, the file\'s own refunds counted, is refused', () {
      final found = read(
        book(),
        '${bought}2026-10-02,退款,600,銀行,,r1,s1,\n'
        '2026-10-03,退款,500,銀行,,r2,s1,\n',
      );
      // 1,000 - 600 = 400 left: 500 is more.
      expect(found.problems, ['第 4 行：找不到可以退款的原支出']);
    });

    test('what is kept is added', () {
      final ledger = book();
      final found = read(ledger, '${bought}2026-10-02,退款,500,現金,,r1,s1,\n');
      addImport(ledger.entryCommands, found);
      // 1,000 - 500 = 500 left.
      expect(
        ledger.entryQueryService.refundable(ledger.entries.byId('s1')!),
        500,
      );
    });
  });

  group('a 群組 of the file (review 37 2)', () {
    Entry old(String id, String group) => entryOf(
      id,
      day(2026, 9, 1),
      EntryType.expense,
      100,
      'bank',
      category: '飲食',
    ).withLinks(group: group);
    Ledger book([List<Entry> entries = const []]) => ledgerOf(
      today: day(2026, 10, 20),
      categories: [Category('飲食', 'food', 0xFF111111)],
      entries: entries,
    );
    // Exception to glossary: the file format's columns.
    const head = '日期,類型,金額,帳戶,分類,備註,群組\n';
    Import read(Ledger ledger, String rows) =>
        importCsv(importBookOf(ledger), head + rows, fallback: 'bank');

    test('one the book has is never joined', () {
      final ledger = book([old('old1', 'G'), old('old2', 'G')]);
      final found = read(
        ledger,
        '2026-10-01,支出,1000,銀行,飲食,x,G\n'
        '2026-10-02,支出,200,銀行,飲食,y,G\n'
        '2026-10-02,支出,300,銀行,飲食,z,H\n',
      );
      expect(found.problems, isEmpty);
      final [x, y, z] = found.entries;
      // One new group for both lines of G; H, which the book lacks, kept.
      expect(x.group, isNotNull);
      expect(x.group, isNot('G'));
      expect(y.group, x.group);
      expect(z.group, 'H');
      addImport(ledger.entryCommands, found);
      expect(
        [for (final e in ledger.entries.inGroup('G')) e.id],
        ['old1', 'old2'],
      );
      expect(ledger.entries.inGroup(x.group!), hasLength(2));
    });

    test('one of an entry in the trash is not reused', () {
      final ledger = book([old('gone', 'T')]);
      ledger.entryCommands.remove('gone');
      final found = read(ledger, '2026-10-01,支出,1000,銀行,飲食,x,T\n');
      expect(found.entries.single.group, isNotNull);
      expect(found.entries.single.group, isNot('T'));
    });
  });
}
