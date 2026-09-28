import 'package:accounts/accounts.dart';
import 'package:data_exchange/data_exchange.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:test/test.dart';

void main() {
  final sourceWorkspace = WorkspaceId(PublicId.generate());
  final destinationWorkspace = WorkspaceId(PublicId.generate());
  final twd = Currency('TWD', 2);
  final usd = Currency('USD', 2);
  final sourceCash = PublicId.generate();
  final sourceBank = PublicId.generate();

  Account account(
    Currency currency, {
    WorkspaceId? workspace,
    BusinessDate? openedOn,
  }) => Account.open(
    id: PublicId.generate(),
    workspace: workspace ?? destinationWorkspace,
    name: 'Target',
    kind: AccountKind.bank,
    currency: currency,
    openedOn: openedOn ?? BusinessDate(2026, 1, 1),
  );

  SimpleTransaction row(
    PostingKind kind,
    PublicId sourceAccount,
    Currency currency,
    int units,
  ) => SimpleTransaction(
    sourceRecordId: PublicId.generate(),
    date: BusinessDate(2026, 9, 28),
    kind: kind,
    accountId: sourceAccount,
    amount: Money(currency, BigInt.from(units)),
  );

  test('previews exact per-currency income and expense without posting', () {
    final targetCash = account(twd);
    final targetBank = account(usd);
    final mapping = {sourceCash: targetCash, sourceBank: targetBank};
    final batch = SimpleTransactionBatch(sourceWorkspace, [
      row(PostingKind.income, sourceCash, twd, 120),
      row(PostingKind.expense, sourceCash, twd, 50),
      row(PostingKind.income, sourceBank, usd, 75),
    ]);
    final preview = SimpleImportPreview.prepare(
      batch: batch,
      destinationWorkspace: destinationWorkspace,
      accountMapping: mapping,
    );
    mapping.clear();
    expect(preview.sourceWorkspace, sourceWorkspace);
    expect(preview.rows.map((r) => r.number), [1, 2, 3]);
    expect(
      preview.rows.first.source.sourceRecordId,
      batch.records.first.sourceRecordId,
    );
    expect(preview.rows.first.targetAccount.id, targetCash.id);
    expect(preview.incomeUnits, {twd: BigInt.from(120), usd: BigInt.from(75)});
    expect(preview.expenseUnits, {twd: BigInt.from(50)});
    expect(() => preview.rows.clear(), throwsUnsupportedError);
    expect(() => preview.incomeUnits.clear(), throwsUnsupportedError);
  });

  test('aggregate preview totals remain exact beyond one Money bound', () {
    final maximum = Money.maxMinorUnits;
    final batch = SimpleTransactionBatch(sourceWorkspace, [
      for (var i = 0; i < 2; i++)
        SimpleTransaction(
          sourceRecordId: PublicId.generate(),
          date: BusinessDate(2026, 9, 28),
          kind: PostingKind.income,
          accountId: sourceCash,
          amount: Money(twd, maximum),
        ),
    ]);
    final preview = SimpleImportPreview.prepare(
      batch: batch,
      destinationWorkspace: destinationWorkspace,
      accountMapping: {sourceCash: account(twd)},
    );
    expect(preview.incomeUnits[twd], maximum * BigInt.two);
  });

  test('rejects missing and cross-workspace account mapping at source row', () {
    final batch = SimpleTransactionBatch(sourceWorkspace, [
      row(PostingKind.income, sourceCash, twd, 1),
      row(PostingKind.expense, sourceBank, usd, 2),
    ]);
    void expectError(Map<PublicId, Account> mapping, String code) {
      expect(
        () => SimpleImportPreview.prepare(
          batch: batch,
          destinationWorkspace: destinationWorkspace,
          accountMapping: mapping,
        ),
        throwsA(
          isA<ExchangeException>()
              .having((e) => e.code, 'code', code)
              .having((e) => e.row, 'row', 2),
        ),
      );
    }

    expectError({sourceCash: account(twd)}, 'account_mapping_missing');
    expectError({
      sourceCash: account(twd),
      sourceBank: account(usd, workspace: sourceWorkspace),
    }, 'target_workspace_mismatch');
  });

  test('rejects mismatched currency, unavailable account and early date', () {
    final batch = SimpleTransactionBatch(sourceWorkspace, [
      row(PostingKind.expense, sourceCash, twd, 1),
    ]);
    void expectError(Account target, String code) {
      expect(
        () => SimpleImportPreview.prepare(
          batch: batch,
          destinationWorkspace: destinationWorkspace,
          accountMapping: {sourceCash: target},
        ),
        throwsA(
          isA<ExchangeException>()
              .having((e) => e.code, 'code', code)
              .having((e) => e.row, 'row', 1),
        ),
      );
    }

    expectError(account(usd), 'target_currencyMismatch');
    final active = account(twd);
    expectError(
      active.archive(
        workspace: destinationWorkspace,
        expectedVersion: active.version,
      ),
      'target_unavailable',
    );
    expectError(
      account(twd, openedOn: BusinessDate(2026, 10, 1)),
      'target_invalidDate',
    );
    expect(
      () => SimpleImportPreview.prepare(
        batch: SimpleTransactionBatch(sourceWorkspace, []),
        destinationWorkspace: destinationWorkspace,
        accountMapping: {},
      ),
      throwsA(
        isA<ExchangeException>().having((e) => e.code, 'code', 'empty_import'),
      ),
    );
  });
}
