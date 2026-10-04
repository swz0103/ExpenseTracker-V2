import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:reports/reports.dart';
import 'package:test/test.dart';

void main() {
  final twd = Currency('TWD', 2);
  final usd = Currency('USD', 2);

  test('civil month has inclusive leap-year boundaries', () {
    expect(ReportMonth(2024, 2).last.toString(), '2024-02-29');
    expect(ReportMonth(2025, 2).last.toString(), '2025-02-28');
    expect(ReportMonth(9999, 12).last.toString(), '9999-12-31');
    expect(() => ReportMonth(2026, 13), throwsFormatException);
  });

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

  test('a fact keeps one currency', () {
    expect(
      () => MonthlyFact(
        id: PublicId.generate(),
        date: BusinessDate(2026, 9, 2),
        kind: PostingKind.income,
        income: Money(twd, BigInt.one),
        expense: Money(usd, BigInt.zero),
      ),
      throwsA(isA<MoneyException>()),
    );
  });
}
