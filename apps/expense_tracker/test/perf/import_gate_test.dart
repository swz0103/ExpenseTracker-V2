/// R12: a CSV of many lines does not hold the screen still: it is read
/// as CSV on a worker isolate and its lines a slice at a time. Measured
/// as the longest the isolate is held, against the same file imported
/// at once, so it holds on any machine, judged on interleaved pairs the
/// host did not stall (held.dart, `shareOf`); the limit is the one the
/// batch writes keep (batch_write_gate_test.dart, 0.045).
@Tags(['timing'])
library;

import 'package:expense_tracker/src/app/demo/seed.dart';
import 'package:expense_tracker/src/features/import_export/model/import_export.dart';
import 'package:expense_tracker/src/features/import_export/ui/import_page.dart'
    show importBookOf;
import 'package:flutter_test/flutter_test.dart';

import '../support/held.dart';

void main() {
  const limit = 0.045;

  /// 100,000 lines, a category of its own every fifth one (the slow path
  /// review 12 found: categories looked for line by line).
  final text = StringBuffer('日期,類型,金額,帳戶,分類,備註\n');
  for (var i = 0; i < 100000; i++) {
    text.write(
      '2026-${1 + i % 9}-${1 + i % 28},支出,${1 + i % 900},隨身現金,'
      '分類${i ~/ 5},第 $i 筆\n',
    );
  }
  final csv = text.toString();

  test('100,000 lines imported apart hold the screen under 4.5% of the '
      'import at once', () async {
    // The book is made before the clock runs: only the import is timed.
    // Interleaved pairs, the one apart first in each (held.dart).
    final result = await shareOf(
      apart: () {
        final book = importBookOf(demoLedger());
        return timeHeld(() => importCsvApart(book, csv, fallback: 'cash'));
      },
      whole: () {
        final book = importBookOf(demoLedger());
        return timeHeld(() async => importCsv(book, csv, fallback: 'cash'));
      },
      limit: limit,
    );
    expectShare(result, 'import_block');
  }, timeout: const Timeout(Duration(minutes: 10)));

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
}
