import 'package:expense_tracker/src/app/demo/seed.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/features/reports/model/report.dart';
import 'package:expense_tracker/src/features/reports/model/report_period.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../baseline/baseline_ledger.dart';

void main() {
  final ledger = demoLedger();
  final period = ReportPeriod.range(
    DateTime.utc(2026, 9, 1),
    DateTime.utc(2026, 9, 30),
  );
  final inSeptember = [
    for (final e in ledger.entries.all)
      if (e.date.year == 2026 && e.date.month == 9) e,
  ];

  Report report() => Report.of(
    period,
    entries: ledger.entries,
    reports: ledger.reportService,
    balances: ledger.balanceService,
    today: ledger.today,
  );

  test('the period holds its own entries only', () {
    final between = Report.entriesBetween(
      ledger.entries,
      period.from,
      period.to,
    );
    expect(between.map((e) => e.id).toSet(), {
      for (final e in inSeptember) e.id,
    });
  });

  test('income, spending and the count are the period\'s entries', () {
    final r = report();
    expect(r.count, inSeptember.length);
    expect(r.income, inSeptember.fold(0, (n, e) => n + e.earning));
    expect(r.expense, inSeptember.fold(0, (n, e) => n + e.spending));
  });

  test('what was spent under one category, parts of splits included', () {
    final name = inSeptember
        .firstWhere((e) => e.type == EntryType.expense)
        .category;
    final (under, total) = Report.spentUnder(name, ledger.entries, period);
    final expected = [
      for (final e in inSeptember)
        for (final (category, amount) in e.spendingParts)
          if (category == name) amount,
    ];
    expect(total, expected.fold(0, (n, a) => n + a));
    expect(under, isNotEmpty);
    for (var i = 1; i < under.length; i++) {
      expect(under[i - 1].date.isBefore(under[i].date), isFalse);
    }
  });

  group('F34: the average per month', () {
    final book = ledgerOf(
      today: DateTime.utc(2026, 10, 9),
      categories: [Category('飲食', 'food', 0xFF5C9A83)],
      entries: [
        entryOf(
          'a',
          DateTime.utc(2026, 8, 10),
          EntryType.expense,
          1000,
          'bank',
        ),
        entryOf(
          's',
          DateTime.utc(2026, 9, 10),
          EntryType.expense,
          2001,
          'bank',
        ),
        entryOf('o', DateTime.utc(2026, 10, 5), EntryType.expense, 500, 'bank'),
      ],
    );
    Report of(ReportPeriod p) => Report.of(
      p,
      entries: book.entries,
      reports: book.reportService,
      balances: book.balanceService,
      today: book.today,
    );

    test('counts whole months only, rounded half away from zero', () {
      // August and September are over: (1,000 + 2,001) / 2 = 1,500.5,
      // rounded to 1,501. October is under way and left out; counted as
      // a whole month and truncated it was 3,501 / 3 = 1,167.
      final r = of(
        ReportPeriod.range(
          DateTime.utc(2026, 8, 1),
          DateTime.utc(2026, 10, 31),
        ),
      );
      expect(r.perStretch, 1501);
    });

    test('with no whole month, the month so far as it is', () {
      // Only October, 9 days in: 500 spent so far.
      final r = of(
        ReportPeriod.range(
          DateTime.utc(2026, 10, 1),
          DateTime.utc(2026, 10, 31),
        ),
      );
      expect(r.perStretch, 500);
    });
  });

  test('a category nothing was spent under has nothing', () {
    final (under, total) = Report.spentUnder('沒有這類', ledger.entries, period);
    expect(under, isEmpty);
    expect(total, 0);
  });
}
