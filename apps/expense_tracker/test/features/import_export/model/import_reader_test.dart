import 'dart:io';
import 'dart:math';

import 'package:domain/data_exchange.dart';
import 'package:expense_tracker/src/app/demo/seed.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/ledger/persistence/codec/record_shape.dart';
import 'package:expense_tracker/src/features/import_export/model/import_export.dart';
import 'package:expense_tracker/src/features/import_export/ui/import_page.dart'
    show importBookOf;
import 'package:flutter_test/flutter_test.dart';

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
      expect(found.problems, ['第 4 行：台幣金額超過原支出還可退的 2,210', '第 5 行：台幣金額要大於 0']);
    });

    test('with no rate and no worth written, the column is named', () {
      final found = read('2026-09-01,支出,100,美元戶,Shop,\n', currency: 'GBP');
      expect(found.problems, ['第 2 行：還沒有匯率，請在「台幣金額」欄填折合新台幣的金額']);
    });
  });
}
