import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:test/test.dart';

import 'fails.dart';

void main() {
  final ws = WorkspaceId(PublicId.generate());
  final usd = Currency('USD', 2), jpy = Currency('JPY', 0);
  PostingAccount ref(Currency c) => PostingAccount(
    id: PublicId.generate(),
    workspace: ws,
    currency: c,
    expectedVersion: 1,
  );
  final a = ref(usd), b = ref(jpy);
  Posting transfer({
    Money? sent,
    Money? received,
    Money? fee,
    PostingAccount? target,
    List<Allocation> allocations = const [],
  }) => Posting.transfer(
    id: PublicId.generate(),
    operation: OperationKey(ws, OperationId(PublicId.generate())),
    date: BusinessDate(2026, 9, 28),
    source: a,
    destination: target ?? b,
    principal: sent ?? Money.parse(usd, '3'),
    received: received ?? Money.parse(jpy, '100'),
    fee: fee ?? Money.parse(usd, '0.25'),
    allocations: allocations,
  );
  test('actual principals preserve recurring exact ratio and exclude source fee from rate', () {
    final p = transfer();
    expect(p.conversion!.rate.numerator, BigInt.from(100));
    expect(p.conversion!.rate.denominator, BigInt.from(3));
    expect(
      p.conversion!.rate.convert(Money.parse(usd, '3')),
      Money.parse(jpy, '100'),
    );
    expect(rebuildBalance(a, [p]), Money.parse(usd, '-3.25'));
    expect(rebuildBalance(b, [p]), Money.parse(jpy, '100'));
    expect(p.reportIncome, Money.parse(usd, '0'));
    expect(p.reportExpense, Money.parse(usd, '0.25'));
  });
  test('invalid amounts, mismatched destination and fee currencies and same currency unequal principals reject', () {
    final usd3 = Currency('USD', 3);
    for (final (make, code) in [
      (
        () => transfer(received: Money.parse(jpy, '0')),
        LedgerError.invalidAmount,
      ),
      (
        () => transfer(received: Money.parse(jpy, '-1')),
        LedgerError.invalidAmount,
      ),
      (
        () => transfer(received: Money.parse(usd, '100')),
        LedgerError.currencyMismatch,
      ),
      (
        () => transfer(fee: Money.parse(Currency('EUR', 2), '1')),
        LedgerError.currencyMismatch,
      ),
      (() => transfer(fee: Money.parse(usd, '-1')), LedgerError.invalidAmount),
      (
        () => transfer(target: ref(usd), received: Money.parse(usd, '2')),
        LedgerError.currencyMismatch,
      ),
      (
        () => transfer(target: ref(usd3), received: Money.parse(usd3, '3')),
        LedgerError.currencyMismatch,
      ),
    ]) {
      expect(make, fails(code));
    }
  });
  test(
    '64-bit principals remain exact and overflow cannot silently quantize',
    () {
      final p = transfer(
        sent: Money(usd, Money.maxMinorUnits),
        received: Money(jpy, Money.maxMinorUnits),
        fee: Money.parse(usd, '0'),
      );
      expect(p.conversion!.rate, FxRate.parse(usd, jpy, '100'));
      expect(() => transfer(sent: Money(usd, Money.maxMinorUnits)), overflows);
    },
  );
  test('a fee in the destination currency comes out of what arrives', () {
    final fee = Money.parse(jpy, '15');
    final p = transfer(fee: fee);
    expect(rebuildBalance(a, [p]), Money.parse(usd, '-3'));
    expect(rebuildBalance(b, [p]), Money.parse(jpy, '85'));
    expect(p.reportIncome, Money.parse(jpy, '0'));
    expect(p.reportExpense, fee);
    expect(p.conversion!.rate.numerator, BigInt.from(100));
  });
  test('the fee can be split into expense categories', () {
    final bankFees = PublicId.generate();
    final p = transfer(
      allocations: [Allocation(bankFees, Money.parse(usd, '0.25'))],
    );
    expect(p.allocations.single.categoryId, bankFees);
    expect(
      () => transfer(
        allocations: [Allocation(bankFees, Money.parse(usd, '0.20'))],
      ),
      fails(LedgerError.allocationMismatch),
    );
  });
}
