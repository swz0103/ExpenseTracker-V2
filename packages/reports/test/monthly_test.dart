import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:reports/reports.dart';
import 'package:test/test.dart';

void main() {
  final twd = Currency('TWD', 2);
  final usd = Currency('USD', 2);
  final month = ReportMonth(2026, 9);
  MonthlyFact fact(
    PostingKind kind,
    BusinessDate date,
    Currency currency,
    String income,
    String expense,
  ) => MonthlyFact(
    id: PublicId.generate(),
    date: date,
    kind: kind,
    income: Money.parse(currency, income),
    expense: Money.parse(currency, expense),
  );

  test('civil month has inclusive leap-year boundaries', () {
    expect(ReportMonth(2024, 2).last.toString(), '2024-02-29');
    expect(ReportMonth(2025, 2).last.toString(), '2025-02-28');
    expect(ReportMonth(9999, 12).last.toString(), '9999-12-31');
    expect(() => ReportMonth(2026, 13), throwsFormatException);
  });

  test(
    'income, purchase, refund, reversal and transfer fee never double count',
    () {
      final day = BusinessDate(2026, 9, 28);
      final rows = [
        fact(PostingKind.opening, day, twd, '0', '0'),
        fact(PostingKind.income, day, twd, '100', '0'),
        fact(PostingKind.expense, day, twd, '0', '40'),
        fact(PostingKind.refund, day, twd, '0', '-10'),
        fact(PostingKind.reversal, day, twd, '-5', '-4'),
        fact(PostingKind.transfer, day, twd, '0', '2'),
        fact(PostingKind.transfer, day, usd, '0', '0'),
      ];
      final report = MonthlyReport.build(month, rows);
      expect(report.currencies, hasLength(1));
      final twdSummary = report.currencies.single;
      expect(twdSummary.income.majorText, '95.00');
      expect(twdSummary.expense.majorText, '28.00');
      expect(twdSummary.net.majorText, '67.00');
      expect(twdSummary.facts, hasLength(5));
    },
  );

  test('currencies remain separate and signed refunds remain visible', () {
    final day = BusinessDate(2026, 9, 1);
    final report = MonthlyReport.build(month, [
      fact(PostingKind.refund, day, twd, '0', '-2'),
      fact(PostingKind.income, day, usd, '7', '0'),
    ]);
    expect(report.currencies.map((row) => row.currency.code), ['TWD', 'USD']);
    expect(report.currencies.first.expense.majorText, '-2.00');
    expect(report.currencies.last.income.majorText, '7.00');
  });

  test(
    'out-of-period, duplicate, mismatched currency and overflow fail closed',
    () {
      final day = BusinessDate(2026, 9, 1);
      final row = fact(PostingKind.income, day, twd, '1', '0');
      expect(
        () => MonthlyReport.build(month, [row, row]),
        throwsFormatException,
      );
      expect(
        () => MonthlyReport.build(month, [
          fact(PostingKind.income, BusinessDate(2026, 10, 1), twd, '1', '0'),
        ]),
        throwsFormatException,
      );
      expect(
        () => MonthlyFact(
          id: PublicId.generate(),
          date: day,
          kind: PostingKind.income,
          income: Money(twd, BigInt.one),
          expense: Money(usd, BigInt.zero),
        ),
        throwsA(isA<MoneyException>()),
      );
      expect(
        () => MonthlyReport.build(month, [
          for (var i = 0; i < 2; i++)
            MonthlyFact(
              id: PublicId.generate(),
              date: day,
              kind: PostingKind.income,
              income: Money(twd, Money.maxMinorUnits),
              expense: Money(twd, BigInt.zero),
            ),
        ]),
        throwsA(isA<MoneyException>()),
      );
    },
  );
}
