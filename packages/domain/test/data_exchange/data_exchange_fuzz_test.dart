import 'dart:io';
import 'dart:math';

import 'package:core/foundation_values.dart';
import 'package:domain/data_exchange.dart';
import 'package:test/test.dart';

/// R12: CSV text and ministry files made at random and mutated (seeded).
/// Reading only ever refuses with a FormatException, whatever it is
/// given; what it reads writes back and reads again the same; invoices
/// come once each, oldest first; every date read is from 1950 on. A few
/// thousand cases here; `FUZZ_CASES=100000` for a nightly run.
void main() {
  final cases = int.tryParse(Platform.environment['FUZZ_CASES'] ?? '') ?? 3000;
  const header = '載具名稱,發票號碼,發票日期,賣方名稱,發票狀態,消費明細_品名,消費明細_金額';
  const good = [
    '手機條碼,AB00000002,20261003,全家便利商店,開立,"拿鐵, 大杯",65',
    '手機條碼,AB00000002,20261003,全家便利商店,開立,御飯糰,39',
    '手機條碼,AB00000001,20261001,誠品,開立,書,380.5',
    '手機條碼,AB00000003,20261002,某超市,作廢,牛奶,95',
  ];
  const fragments = [
    ',', ',', '"', '""', '\n', '\r\n', '\r', "'", '=', '+', '-', '@', //
    '\t', ' ', '\u{FEFF}', '\u0000', '😀', '中', '20261003', '19491231',
    'AB00000001', '作廢', '開立', '12', '1.5', '-3', '1e3', '9999999999999',
  ];

  String junk(Random r, int most) => [
    for (var i = 0, n = r.nextInt(most); i < n; i++)
      fragments[r.nextInt(fragments.length)],
  ].join();

  String mutate(Random r, String text) {
    var t = text;
    for (var k = 1 + r.nextInt(4); k > 0; k--) {
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
              String.fromCharCode(r.nextInt(0x3000)) +
              t.substring(at),
      };
    }
    return t;
  }

  final file = '\u{FEFF}$header\r\n${good.join('\r\n')}\r\n';

  test('$cases texts: CSV reads, or refuses with the line', () {
    final r = Random(4242);
    final corpus = [file, header, 'a,b\n1,2', '"a""b",c\r\n'];
    for (var i = 0; i < cases; i++) {
      final text = i.isEven
          ? junk(r, 30)
          : mutate(r, corpus[r.nextInt(corpus.length)]);
      try {
        final records = readCsvRecords(text);
        var line = 0;
        for (final record in records) {
          expect(record.cells.any((c) => c.isNotEmpty), isTrue);
          expect(record.line, greaterThan(line), reason: 'lines go on');
          line = record.line;
        }
        final rows = [for (final record in records) record.cells];
        expect(readCsv(writeCsv(rows)), rows, reason: '${text.codeUnits}');
      } on CsvFormatException catch (error) {
        expect(error.line, greaterThanOrEqualTo(1));
      }
    }
  });

  test('$cases ministry files: invoices once each, oldest first', () {
    final r = Random(4243);
    for (var i = 0; i < cases; i++) {
      final text = i % 3 == 0 ? '$header\n${junk(r, 25)}' : mutate(r, file);
      final EInvoiceFile read;
      try {
        read = readEInvoices(text);
      } on FormatException {
        continue;
      }
      final numbers = <String>{};
      BusinessDate? before;
      for (final invoice in read.invoices) {
        expect(numbers.add(invoice.number), isTrue, reason: 'once each');
        expect(invoice.date.year, greaterThanOrEqualTo(earliestImportYear));
        if (before != null)
          expect(before.compareTo(invoice.date), lessThanOrEqualTo(0));
        before = invoice.date;
      }
      for (final refused in read.refused) {
        expect(numbers.add(refused.number), isTrue, reason: 'once each');
      }
    }
  });

  test('$cases texts as days: a date from 1950 on, or why not', () {
    final r = Random(4244);
    for (var i = 0; i < cases; i++) {
      final text = junk(r, 6);
      switch (readImportDay(text)) {
        case DayRead(:final date):
          expect(date.year, greaterThanOrEqualTo(earliestImportYear));
        case DayRefused():
          break;
      }
    }
  });
}
