import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:test/test.dart';

void main() {
  final ws = WorkspaceId(PublicId.generate()),
      original = PublicId.generate(),
      category = PublicId.generate(),
      other = PublicId.generate();
  final usd = Currency('USD', 2), jpy = Currency('JPY', 0);
  Money m(String n) => Money.parse(usd, n);
  Allocation a(PublicId id, String n, {int version = 1}) =>
      Allocation(id, m(n), expectedCategoryVersion: version);
  RefundBudget budget() => RefundBudget(
    originalId: original,
    originalDate: BusinessDate(2026, 9, 1),
    amount: m('10'),
    allocations: [a(category, '6'), a(other, '4')],
  );
  final date = BusinessDate(2026, 9, 28);
  test(
    'partial then full refund preserves exact remaining category authority',
    () {
      final partial = budget().consume(
        amount: m('2'),
        date: date,
        allocations: [a(other, '2')],
      );
      expect(partial.remaining, m('8'));
      expect(
        partial.allocations.singleWhere((r) => r.categoryId == other).amount,
        m('2'),
      );
      final full = partial.consume(
        amount: m('8'),
        date: date,
        allocations: [a(category, '6'), a(other, '2')],
      );
      expect(full.remaining, m('0'));
      expect(full.allocations, isEmpty);
      expect(
        () => full.consume(amount: m('0.01'), date: date, allocations: []),
        throwsA(isA<LedgerException>()),
      );
      expect(budget().remaining, m('10'));
    },
  );
  test(
    'amount, category, version, duplicate, date and denomination limits reject',
    () {
      for (final rows in [
        [a(category, '7')],
        [a(category, '2', version: 2)],
        [a(PublicId.generate(), '2')],
        [a(category, '1'), a(category, '1')],
        <Allocation>[],
      ]) {
        final amount = rows.isEmpty
            ? m('2')
            : rows.fold(m('0'), (Money sum, r) => sum + r.amount);
        expect(
          () => budget().consume(amount: amount, date: date, allocations: rows),
          throwsA(isA<LedgerException>()),
        );
      }
      expect(
        () => budget().consume(
          amount: m('2'),
          date: BusinessDate(2026, 8, 31),
          allocations: [a(category, '2')],
        ),
        throwsA(isA<LedgerException>()),
      );
      expect(
        () => budget().consume(
          amount: Money.parse(jpy, '2'),
          date: date,
          allocations: [],
        ),
        throwsA(isA<LedgerException>()),
      );
      for (final n in ['0', '-1', '11']) {
        expect(
          () => budget().consume(amount: m(n), date: date, allocations: []),
          throwsA(isA<LedgerException>()),
        );
      }
    },
  );
  test(
    'FX refund separates original expense from actual cash without income',
    () {
      final p = Posting.refund(
        id: PublicId.generate(),
        operation: OperationKey(ws, OperationId(PublicId.generate())),
        date: date,
        account: PostingAccount(
          id: PublicId.generate(),
          workspace: ws,
          currency: jpy,
          expectedVersion: 1,
        ),
        originalId: original,
        amount: m('2'),
        received: Money.parse(jpy, '310'),
      );
      expect(p.reportIncome, m('0'));
      expect(p.reportExpense, m('-2'));
      expect(p.legs.single.amount, Money.parse(jpy, '310'));
      expect(p.conversion, isNotNull);
      expect(p.refundOf, original);
    },
  );
  test('same denomination cannot conceal differing cash or self-reference', () {
    final account = PostingAccount(
      id: PublicId.generate(),
      workspace: ws,
      currency: usd,
      expectedVersion: 1,
    );
    Posting make(PublicId id, Money received) => Posting.refund(
      id: id,
      operation: OperationKey(ws, OperationId(PublicId.generate())),
      date: date,
      account: account,
      originalId: original,
      amount: m('2'),
      received: received,
    );
    expect(
      () => make(PublicId.generate(), m('3')),
      throwsA(isA<LedgerException>()),
    );
    expect(() => make(original, m('2')), throwsA(isA<LedgerException>()));
    expect(make(PublicId.generate(), m('2')).conversion, isNull);
  });
}
