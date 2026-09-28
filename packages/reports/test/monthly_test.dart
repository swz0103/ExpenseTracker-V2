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
    'historical split and signed refunds reconcile with currency totals',
    () {
      final food = PublicId.generate(), travel = PublicId.generate();
      final expense = MonthlyFact(
        id: PublicId.generate(),
        date: BusinessDate(2026, 9, 2),
        kind: PostingKind.expense,
        income: Money(twd, BigInt.zero),
        expense: Money.parse(twd, '10'),
        allocations: [
          CategoryAllocation(food, Money.parse(twd, '6')),
          CategoryAllocation(travel, Money.parse(twd, '4')),
        ],
      );
      final refund = MonthlyFact(
        id: PublicId.generate(),
        date: BusinessDate(2026, 9, 3),
        kind: PostingKind.refund,
        income: Money(twd, BigInt.zero),
        expense: Money.parse(twd, '-2'),
        allocations: [CategoryAllocation(food, Money.parse(twd, '2'))],
      );
      final fee = fact(
        PostingKind.transfer,
        BusinessDate(2026, 9, 4),
        twd,
        '0',
        '1',
      );
      final report = MonthlyReport.build(month, [expense, refund, fee]);
      expect(report.currencies.single.expense.majorText, '9.00');
      final byCategory = {
        for (final row in report.categories) row.categoryId: row,
      };
      expect(byCategory[food]!.expense.majorText, '4.00');
      expect(byCategory[food]!.facts.map((row) => row.source.id), {
        expense.id,
        refund.id,
      });
      expect(byCategory[travel]!.expense.majorText, '4.00');
      expect(byCategory[null]!.expense.majorText, '1.00');
      expect(
        report.categories.fold<BigInt>(
          BigInt.zero,
          (sum, row) => sum + row.expense.minorUnits,
        ),
        report.currencies.single.expense.minorUnits,
      );
    },
  );

  test('invalid category attribution fails closed', () {
    final id = PublicId.generate();
    MonthlyFact row(List<CategoryAllocation> allocations) => MonthlyFact(
      id: PublicId.generate(),
      date: BusinessDate(2026, 9, 2),
      kind: PostingKind.expense,
      income: Money(twd, BigInt.zero),
      expense: Money.parse(twd, '5'),
      allocations: allocations,
    );
    expect(
      () => row([CategoryAllocation(id, Money.parse(twd, '4'))]),
      throwsFormatException,
    );
    expect(
      () => row([
        CategoryAllocation(id, Money.parse(twd, '2')),
        CategoryAllocation(id, Money.parse(twd, '3')),
      ]),
      throwsFormatException,
    );
    expect(
      () => row([CategoryAllocation(id, Money.parse(usd, '5'))]),
      throwsA(isA<MoneyException>()),
    );
  });

  test('saved merchant identities reconcile, including refunds and fees', () {
    final shop = PublicId.generate(), incomeMerchant = PublicId.generate();
    MonthlyFact row(
      PostingKind kind,
      String income,
      String expense,
      PublicId? merchant,
    ) => MonthlyFact(
      id: PublicId.generate(),
      date: BusinessDate(2026, 9, 2),
      kind: kind,
      income: Money.parse(twd, income),
      expense: Money.parse(twd, expense),
      merchantId: merchant,
    );
    final expense = row(PostingKind.expense, '0', '10', shop);
    final refund = row(PostingKind.refund, '0', '-3', shop);
    final transferFee = row(PostingKind.transfer, '0', '1', null);
    final income = row(PostingKind.income, '12', '0', incomeMerchant);
    final report = MonthlyReport.build(month, [
      expense,
      refund,
      transferFee,
      income,
    ]);
    final byMerchant = {
      for (final summary in report.merchants) summary.merchantId: summary,
    };
    expect(byMerchant[shop]!.expense.majorText, '7.00');
    expect(byMerchant[shop]!.facts.map((fact) => fact.id), [
      expense.id,
      refund.id,
    ]);
    expect(byMerchant[null]!.expense.majorText, '1.00');
    expect(byMerchant[incomeMerchant]!.income.majorText, '12.00');
    expect(
      report.merchants.fold<BigInt>(
        BigInt.zero,
        (sum, summary) => sum + summary.expense.minorUnits,
      ),
      report.currencies.single.expense.minorUnits,
    );
    expect(
      report.merchants.fold<BigInt>(
        BigInt.zero,
        (sum, summary) => sum + summary.income.minorUnits,
      ),
      report.currencies.single.income.minorUnits,
    );
  });

  test(
    'account attribution uses report currency even for foreign refund cash',
    () {
      final cash = PublicId.generate(), foreign = PublicId.generate();
      MonthlyFact row(
        PostingKind kind,
        Currency currency,
        String income,
        String expense,
        PublicId account,
      ) => MonthlyFact(
        id: PublicId.generate(),
        date: BusinessDate(2026, 9, 2),
        kind: kind,
        income: Money.parse(currency, income),
        expense: Money.parse(currency, expense),
        accountId: account,
      );
      final report = MonthlyReport.build(month, [
        row(PostingKind.expense, twd, '0', '10', cash),
        row(PostingKind.transfer, twd, '0', '1', cash),
        row(PostingKind.refund, twd, '0', '-3', foreign),
        row(PostingKind.income, usd, '12', '0', foreign),
      ]);
      final byAccount = {
        for (final summary in report.accounts)
          (summary.accountId, summary.currency): summary,
      };
      expect(byAccount[(cash, twd)]!.expense.majorText, '11.00');
      expect(byAccount[(foreign, twd)]!.expense.majorText, '-3.00');
      expect(byAccount[(foreign, usd)]!.income.majorText, '12.00');
      for (final currency in report.currencies) {
        expect(
          report.accounts
              .where((row) => row.currency == currency.currency)
              .fold<BigInt>(
                BigInt.zero,
                (sum, row) => sum + row.income.minorUnits,
              ),
          currency.income.minorUnits,
        );
        expect(
          report.accounts
              .where((row) => row.currency == currency.currency)
              .fold<BigInt>(
                BigInt.zero,
                (sum, row) => sum + row.expense.minorUnits,
              ),
          currency.expense.minorUnits,
        );
      }
    },
  );

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
