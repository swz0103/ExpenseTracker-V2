import 'package:expense_tracker/src/app/demo/seed.dart';
import 'package:expense_tracker/src/features/import_export/model/import_export.dart';
import 'package:expense_tracker/src/features/import_export/ui/import_page.dart'
    show importBookOf;
import 'package:flutter_test/flutter_test.dart';

import '../support/held.dart';

/// R12: a CSV of many lines does not hold the screen still: it is read
/// as CSV on a worker isolate and its lines a slice at a time. Measured
/// as the longest the isolate is held, against the same file imported
/// at once, so it holds on any machine; the limit is the one the batch
/// writes keep (batch_write_gate_test.dart, 0.045).
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
    final apart = await leastOf(gateTries, () async {
      final book = importBookOf(demoLedger());
      return (await timeHeld(() => importCsvApart(book, csv, fallback: 'cash')))
          .heldUs;
    });
    final atOnce = await leastOf(gateTries, () async {
      final book = importBookOf(demoLedger());
      return (await timeHeld(
        () async => importCsv(book, csv, fallback: 'cash'),
      )).heldUs;
    });
    final share = apart / atOnce;
    // ignore: avoid_print
    print('import held: apart $apart us, at once $atOnce us, share $share');
    expect(share, lessThan(limit));
  }, timeout: const Timeout(Duration(minutes: 5)));

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
