import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:test/test.dart';

void main() {
  final ws = WorkspaceId(PublicId.generate()), currency = Currency('USD', 2);
  final account = PostingAccount(
    id: PublicId.generate(),
    workspace: ws,
    currency: currency,
    expectedVersion: 1,
  );
  Money money(String value) => Money.parse(currency, value);
  Posting income(List<Allocation> allocations) => Posting.income(
    id: PublicId.generate(),
    operation: OperationKey(ws, OperationId(PublicId.generate())),
    date: BusinessDate(2026, 9, 27),
    account: account,
    amount: money('10'),
    allocations: allocations,
  );
  test(
    'income allocation is immutable attribution and does not add a cash leg',
    () {
      final source = [
        Allocation(PublicId.generate(), money('6'), expectedCategoryVersion: 2),
        Allocation(PublicId.generate(), money('4'), expectedCategoryVersion: 1),
      ];
      final posting = income(source);
      source.clear();
      expect(posting.allocations, hasLength(2));
      expect(posting.legs, hasLength(1));
      expect(rebuildBalance(account, [posting]), money('10'));
      expect(posting.allocations.first.expectedCategoryVersion, 2);
      expect(() => posting.allocations.clear(), throwsUnsupportedError);
    },
  );
  test('income uses the same exact sum currency and duplicate constraints as expense', () {
    final id = PublicId.generate();
    for (final proposal in [
      [Allocation(id, money('9'))],
      [Allocation(id, money('5')), Allocation(id, money('5'))],
      [Allocation(id, Money.parse(Currency('EUR', 2), '10'))],
    ]) {
      expect(() => income(proposal), throwsA(isA<LedgerException>()));
    }
    expect(
      () => Allocation(id, money('10'), expectedCategoryVersion: 0),
      throwsArgumentError,
    );
    expect(
      () => Allocation(id, money('10'), expectedCategoryVersion: -1),
      throwsArgumentError,
    );
  });
}
