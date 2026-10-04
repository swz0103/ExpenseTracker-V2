import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:test/test.dart';

import 'fails.dart';

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
        fails(LedgerError.refundLimit),
      );
      expect(budget().remaining, m('10'));
    },
  );
  test(
    'amount, category, version, duplicate, date and denomination limits reject',
    () {
      for (final (rows, code) in [
        ([a(category, '7')], LedgerError.refundLimit),
        ([a(category, '2', version: 2)], LedgerError.refundReference),
        ([a(PublicId.generate(), '2')], LedgerError.refundReference),
        ([a(category, '1'), a(category, '1')], LedgerError.duplicateIdentity),
        (<Allocation>[], LedgerError.refundReference),
      ]) {
        final amount = rows.isEmpty
            ? m('2')
            : rows.fold(m('0'), (Money sum, r) => sum + r.amount);
        expect(
          () => budget().consume(amount: amount, date: date, allocations: rows),
          fails(code),
        );
      }
      expect(
        () => budget().consume(
          amount: m('2'),
          date: BusinessDate(2026, 8, 31),
          allocations: [a(category, '2')],
        ),
        fails(LedgerError.refundReference),
      );
      expect(
        () => budget().consume(
          amount: Money.parse(jpy, '2'),
          date: date,
          allocations: [],
        ),
        fails(LedgerError.currencyMismatch),
      );
      for (final (n, code) in [
        ('0', LedgerError.invalidAmount),
        ('-1', LedgerError.invalidAmount),
        ('11', LedgerError.refundLimit),
      ]) {
        expect(
          () => budget().consume(amount: m(n), date: date, allocations: []),
          fails(code),
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
      fails(LedgerError.currencyMismatch),
    );
    expect(() => make(original, m('2')), fails(LedgerError.refundReference));
    expect(make(PublicId.generate(), m('2')).conversion, isNull);
  });
}
