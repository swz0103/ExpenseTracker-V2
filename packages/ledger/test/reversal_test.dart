import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:test/test.dart';

void main() {
  final ws = WorkspaceId(PublicId.generate()),
      usd = Currency('USD', 2),
      jpy = Currency('JPY', 0),
      date = BusinessDate(2026, 9, 28);
  OperationKey op([WorkspaceId? w]) =>
      OperationKey(w ?? ws, OperationId(PublicId.generate()));
  PostingAccount a(Currency c) => PostingAccount(
    id: PublicId.generate(),
    workspace: ws,
    currency: c,
    expectedVersion: 1,
  );
  final x = a(usd), y = a(jpy);
  final amount = Money(usd, Money.maxMinorUnits);
  Posting rev(
    Posting p, {
    BusinessDate? when,
    PublicId? id,
    OperationKey? key,
    String reason = '',
  }) => Posting.reversal(
    id: id ?? PublicId.generate(),
    operation: key ?? op(),
    date: when ?? date,
    original: p,
    reason: reason,
  );
  test('exact inverse retains original; max Money and FX fees sum to zero without doubles', () {
    final sources = [
      Posting.income(
        id: PublicId.generate(),
        operation: op(),
        date: date,
        account: x,
        amount: amount,
      ),
      Posting.expense(
        id: PublicId.generate(),
        operation: op(),
        date: date,
        account: x,
        amount: amount,
      ),
      Posting.transfer(
        id: PublicId.generate(),
        operation: op(),
        date: date,
        source: x,
        destination: y,
        principal: Money.parse(usd, '123.45'),
        received: Money.parse(jpy, '18517'),
        fee: Money.parse(usd, '0.07'),
      ),
    ];
    for (final p in sources) {
      final r = rev(p);
      expect(
        r.reportIncome.minorUnits + p.reportIncome.minorUnits,
        BigInt.zero,
      );
      expect(
        r.reportExpense.minorUnits + p.reportExpense.minorUnits,
        BigInt.zero,
      );
      for (final account in [x, y])
        expect(rebuildBalance(account, [p, r]).minorUnits, BigInt.zero);
      expect(r.conversion, same(p.conversion));
      expect(r.reversedPosting, same(p));
      expect(() => r.legs.clear(), throwsUnsupportedError);
    }
  });
  test('self-reference, wrong workspace/date, opening/refund/reversal and invalid reason reject', () {
    final p = Posting.expense(
      id: PublicId.generate(),
      operation: op(),
      date: date,
      account: x,
      amount: amount,
    );
    for (final make in [
      () => rev(p, id: p.id),
      () => rev(p, key: op(WorkspaceId(PublicId.generate()))),
      () => rev(p, when: BusinessDate(2026, 9, 27)),
      () => rev(p, reason: ' bad '),
      () => rev(p, reason: '字' * 257),
      () => rev(rev(p)),
      () => rev(
        Posting.opening(
          id: PublicId.generate(),
          operation: op(),
          date: date,
          account: x,
          amount: amount,
        ),
      ),
      () => rev(
        Posting.refund(
          id: PublicId.generate(),
          operation: op(),
          date: date,
          account: x,
          originalId: p.id,
          amount: amount,
        ),
      ),
    ])
      expect(make, throwsA(isA<LedgerException>()));
    expect(rev(p, reason: '字' * 256).reversalReason!.length, 256);
  });
}
