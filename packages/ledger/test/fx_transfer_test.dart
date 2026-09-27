import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:test/test.dart';

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
  }) => Posting.transfer(
    id: PublicId.generate(),
    operation: OperationKey(ws, OperationId(PublicId.generate())),
    date: BusinessDate(2026, 9, 28),
    source: a,
    destination: target ?? b,
    principal: sent ?? Money.parse(usd, '3'),
    received: received ?? Money.parse(jpy, '100'),
    fee: fee ?? Money.parse(usd, '0.25'),
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
    for (final make in [
      () => transfer(received: Money.parse(jpy, '0')),
      () => transfer(received: Money.parse(jpy, '-1')),
      () => transfer(received: Money.parse(usd, '100')),
      () => transfer(fee: Money.parse(jpy, '1')),
      () => transfer(fee: Money.parse(usd, '-1')),
      () => transfer(target: ref(usd), received: Money.parse(usd, '2')),
      () => transfer(
        target: ref(Currency('USD', 3)),
        received: Money.parse(Currency('USD', 3), '3'),
      ),
    ]) {
      expect(make, throwsA(isA<LedgerException>()));
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
      expect(
        () => transfer(sent: Money(usd, Money.maxMinorUnits)),
        throwsA(isA<MoneyException>()),
      );
    },
  );
}
