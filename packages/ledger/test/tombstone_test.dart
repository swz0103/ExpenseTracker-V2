import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:test/test.dart';

void main() {
  final workspace = WorkspaceId(PublicId.generate());
  final usd = Currency('USD', 2), jpy = Currency('JPY', 0);
  OperationKey op([WorkspaceId? ws]) =>
      OperationKey(ws ?? workspace, OperationId(PublicId.generate()));
  PostingAccount account(Currency currency) => PostingAccount(
    id: PublicId.generate(),
    workspace: workspace,
    currency: currency,
    expectedVersion: 1,
  );
  final source = account(usd), destination = account(jpy);
  final date = BusinessDate(2026, 9, 28);
  Posting expense() => Posting.expense(
    id: PublicId.generate(),
    operation: op(),
    date: date,
    account: source,
    amount: Money.parse(usd, '10'),
  );

  test('tombstone proposal retains original facts without creating a leg', () {
    final original = Posting.transfer(
      id: PublicId.generate(),
      operation: op(),
      date: date,
      source: source,
      destination: destination,
      principal: Money.parse(usd, '10'),
      received: Money.parse(jpy, '1500'),
      fee: Money.parse(usd, '0.10'),
    );
    final tombstone = PostingTombstone(
      original: original,
      operation: op(),
      reason: '誤輸入',
    );
    expect(tombstone.original, same(original));
    expect(tombstone.original.legs, hasLength(3));
    expect(tombstone.reason, '誤輸入');
    // The effective set excludes the original once the marker commits;
    // the marker itself is not another financial event.
    expect(rebuildBalance(source, [original]), Money.parse(usd, '-10.10'));
    expect(rebuildBalance(source, const []), Money.parse(usd, '0'));
  });

  test('opening, same operation, wrong workspace and reason are rejected', () {
    final original = expense();
    final opening = Posting.opening(
      id: PublicId.generate(),
      operation: op(),
      date: date,
      account: source,
      amount: Money.parse(usd, '10'),
    );
    for (final make in [
      () => PostingTombstone(original: opening, operation: op()),
      () => PostingTombstone(original: original, operation: original.operation),
      () => PostingTombstone(
        original: original,
        operation: op(WorkspaceId(PublicId.generate())),
      ),
      () => PostingTombstone(
        original: original,
        operation: op(),
        reason: ' trailing ',
      ),
      () => PostingTombstone(
        original: original,
        operation: op(),
        reason: '字' * 257,
      ),
    ]) {
      expect(make, throwsA(isA<LedgerException>()));
    }
    expect(
      PostingTombstone(
        original: original,
        operation: op(),
        reason: '字' * 256,
      ).reason.runes.length,
      256,
    );
  });
}
