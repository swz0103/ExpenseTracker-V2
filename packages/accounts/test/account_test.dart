import 'package:accounts/accounts.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:test/test.dart';

void main() {
  final workspace = WorkspaceId(PublicId.generate());
  final otherWorkspace = WorkspaceId(PublicId.generate());
  final usd = Currency('USD', 2);
  final date = BusinessDate(2026, 9, 26);
  Account open({WorkspaceId? owner}) => Account.open(
    id: PublicId.generate(),
    workspace: owner ?? workspace,
    name: ' Bank ',
    kind: AccountKind.bank,
    currency: usd,
    openedOn: date,
  );
  Matcher error(AccountError code) =>
      throwsA(isA<AccountException>().having((e) => e.code, 'code', code));
  Account close(
    Account account, {
    Money? balance,
    bool unsettled = false,
    Account? successor,
  }) => account.close(
    workspace: workspace,
    expectedVersion: account.version,
    balanceAccountId: account.id,
    currentBalance: balance ?? Money(usd, BigInt.zero),
    hasUnsettledItems: unsettled,
    date: date,
    reason: 'finished',
    successor: successor,
  );

  test('opening creates active immutable metadata without a balance field', () {
    final account = open();
    expect(account.name, 'Bank');
    expect(account.version, 1);
    expect(account.state, AccountState.active);
    account.requirePosting(
      workspace: workspace,
      currency: usd,
      expectedRulesVersion: 1,
      date: date,
    );
    final renamed = account.rename(
      workspace: workspace,
      expectedVersion: 1,
      name: 'Cash reserve',
    );
    expect(account.name, 'Bank');
    expect(renamed.version, 2);
    expect(renamed.rulesVersion, 1);
    expect(renamed.id, account.id);
    // An entry prepared before the rename still posts (G1-09).
    renamed.requirePosting(
      workspace: workspace,
      currency: usd,
      expectedRulesVersion: 1,
      date: date,
    );
  });
  test('VAL-06 rejects cross-workspace participation and mutation', () {
    final account = open();
    expect(
      () => account.requirePosting(
        workspace: otherWorkspace,
        currency: usd,
        expectedRulesVersion: 1,
        date: date,
      ),
      error(AccountError.workspaceMismatch),
    );
    expect(
      () => account.rename(
        workspace: otherWorkspace,
        expectedVersion: 1,
        name: 'Changed',
      ),
      error(AccountError.workspaceMismatch),
    );
  });
  test('TX-04 stale versions cannot write or change metadata', () {
    final account = open().archive(workspace: workspace, expectedVersion: 1);
    expect(
      () => account.requirePosting(
        workspace: workspace,
        currency: usd,
        expectedRulesVersion: 1,
        date: date,
      ),
      error(AccountError.versionConflict),
    );
    expect(
      () => account.rename(
        workspace: workspace,
        expectedVersion: 1,
        name: 'Changed',
      ),
      error(AccountError.versionConflict),
    );
  });
  test('posting rejects wrong denomination and dates before opening', () {
    final account = open();
    expect(
      () => account.requirePosting(
        workspace: workspace,
        currency: Currency('USD', 3),
        expectedRulesVersion: 1,
        date: date,
      ),
      error(AccountError.currencyMismatch),
    );
    expect(
      () => account.requirePosting(
        workspace: workspace,
        currency: usd,
        expectedRulesVersion: 1,
        date: BusinessDate(2026, 9, 25),
      ),
      error(AccountError.invalidDate),
    );
  });
  test('archive blocks posting and reactivate restores participation', () {
    final archived = open().archive(workspace: workspace, expectedVersion: 1);
    expect(
      () => archived.requirePosting(
        workspace: workspace,
        currency: usd,
        expectedRulesVersion: 2,
        date: date,
      ),
      error(AccountError.unavailable),
    );
    final active = archived.reactivate(
      workspace: workspace,
      expectedVersion: 2,
    );
    active.requirePosting(
      workspace: workspace,
      currency: usd,
      expectedRulesVersion: 3,
      date: date,
    );
  });
  test('closing rejects either sign of balance, unsettled items and wrong currency', () {
    final account = open();
    for (final amount in ['0.01', '-0.01']) {
      expect(
        () => close(account, balance: Money.parse(usd, amount)),
        error(AccountError.nonZeroBalance),
      );
    }
    expect(
      () => close(account, unsettled: true),
      error(AccountError.unsettledItems),
    );
    expect(
      () => close(account, balance: Money(Currency('EUR', 2), BigInt.zero)),
      error(AccountError.currencyMismatch),
    );
    expect(account.state, AccountState.active);
  });
  test('closure preserves identity, metadata and successor; reactivation keeps prior closure', () {
    final account = open();
    final successor = open();
    final closed = close(account, successor: successor);
    expect(closed.id, account.id);
    expect(closed.closedOn, date);
    expect(closed.successorId, successor.id);
    expect(
      () => closed.requirePosting(
        workspace: workspace,
        currency: usd,
        expectedRulesVersion: 2,
        date: date,
      ),
      error(AccountError.unavailable),
    );
    final restored = closed.reactivate(
      workspace: workspace,
      expectedVersion: 2,
    );
    expect(restored.state, AccountState.active);
    expect(restored.closingReason, 'finished');
  });
  test('closing rejects self or foreign workspace successor and wrong balance account', () {
    final account = open();
    expect(
      () => close(account, successor: account),
      error(AccountError.invalidInput),
    );
    expect(
      () => close(account, successor: open(owner: otherWorkspace)),
      error(AccountError.workspaceMismatch),
    );
    expect(
      () => account.close(
        workspace: workspace,
        expectedVersion: 1,
        balanceAccountId: PublicId.generate(),
        currentBalance: Money(usd, BigInt.zero),
        hasUnsettledItems: false,
        date: date,
        reason: 'x',
      ),
      error(AccountError.invalidInput),
    );
  });
  test('net worth exclusion changes display policy, not monetary state', () {
    final account = open();
    final excluded = account.setNetWorthInclusion(
      workspace: workspace,
      expectedVersion: 1,
      included: false,
    );
    expect(excluded.includeInNetWorth, isFalse);
    expect(account.includeInNetWorth, isTrue);
    expect(excluded.version, 2);
    expect(excluded.rulesVersion, 1);
    excluded.requirePosting(
      workspace: workspace,
      currency: usd,
      expectedRulesVersion: 1,
      date: date,
    );
  });
}
