import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:test/test.dart';

import 'fails.dart';

void main() {
  final ws = WorkspaceId(PublicId.generate());
  final usd = Currency('USD', 2);
  final jpy = Currency('JPY', 0);
  final account = PostingAccount(
    id: PublicId.generate(),
    workspace: ws,
    currency: usd,
    expectedVersion: 1,
  );
  final foreign = PostingAccount(
    id: PublicId.generate(),
    workspace: ws,
    currency: jpy,
    expectedVersion: 1,
  );
  OperationKey op([WorkspaceId? workspace]) =>
      OperationKey(workspace ?? ws, OperationId(PublicId.generate()));
  final originalDate = BusinessDate(2026, 9, 28);
  Posting expense() => Posting.expense(
    id: PublicId.generate(),
    operation: op(),
    date: originalDate,
    account: account,
    amount: Money.parse(usd, '10'),
  );

  test('correction keeps source and exactly cancels its financial effect', () {
    final original = expense();
    final replacement = Posting.expense(
      id: PublicId.generate(),
      operation: op(),
      date: BusinessDate(2026, 9, 27),
      account: account,
      amount: Money.parse(usd, '7'),
    );
    final correction = PostingCorrection(
      original: original,
      replacement: replacement,
      reversalId: PublicId.generate(),
      reversalOperation: op(),
      reason: '金額誤植',
    );
    expect(correction.reversal.date, originalDate);
    expect(correction.reversal.reversalOf, original.id);
    expect(correction.reversal.reversalReason, '金額誤植');
    expect(
      rebuildBalance(account, [
        correction.original,
        correction.reversal,
        correction.replacement,
      ]),
      Money.parse(usd, '-7'),
    );
    expect(
      original.reportExpense + correction.reversal.reportExpense,
      Money.parse(usd, '0'),
    );
  });

  test('cross-currency transfer principal and fee cancel independently', () {
    final original = Posting.transfer(
      id: PublicId.generate(),
      operation: op(),
      date: originalDate,
      source: account,
      destination: foreign,
      principal: Money.parse(usd, '10'),
      received: Money.parse(jpy, '1512'),
      fee: Money.parse(usd, '0.03'),
    );
    final replacement = Posting.transfer(
      id: PublicId.generate(),
      operation: op(),
      date: BusinessDate(2026, 10, 1),
      source: account,
      destination: foreign,
      principal: Money.parse(usd, '9'),
      received: Money.parse(jpy, '1361'),
      fee: Money.parse(usd, '0.02'),
    );
    final correction = PostingCorrection(
      original: original,
      replacement: replacement,
      reversalId: PublicId.generate(),
      reversalOperation: op(),
    );
    for (final participating in [account, foreign]) {
      expect(
        rebuildBalance(participating, [
          correction.original,
          correction.reversal,
          correction.replacement,
        ]),
        rebuildBalance(participating, [replacement]),
      );
    }
  });

  test('identity, operation, kind and workspace collisions are rejected', () {
    final original = expense();
    final replacement = Posting.expense(
      id: PublicId.generate(),
      operation: op(),
      date: originalDate,
      account: account,
      amount: Money.parse(usd, '7'),
    );
    PostingCorrection make({
      Posting? source,
      Posting? next,
      PublicId? reversalId,
      OperationKey? reversalOperation,
    }) => PostingCorrection(
      original: source ?? original,
      replacement: next ?? replacement,
      reversalId: reversalId ?? PublicId.generate(),
      reversalOperation: reversalOperation ?? op(),
    );
    expect(
      () => make(reversalId: replacement.id),
      fails(LedgerError.correctionReference),
    );
    expect(
      () => make(reversalOperation: replacement.operation),
      fails(LedgerError.correctionReference),
    );
    expect(
      () => make(reversalOperation: original.operation),
      fails(LedgerError.correctionReference),
    );
    expect(
      () => make(reversalOperation: op(WorkspaceId(PublicId.generate()))),
      fails(LedgerError.workspaceMismatch),
    );
    expect(
      () => make(
        next: Posting.income(
          id: PublicId.generate(),
          operation: op(),
          date: originalDate,
          account: account,
          amount: Money.parse(usd, '7'),
        ),
      ),
      fails(LedgerError.correctionReference),
    );
    expect(
      () => make(
        source: Posting.opening(
          id: PublicId.generate(),
          operation: op(),
          date: originalDate,
          account: account,
          amount: Money.parse(usd, '10'),
        ),
      ),
      fails(LedgerError.correctionReference),
    );
  });
}
