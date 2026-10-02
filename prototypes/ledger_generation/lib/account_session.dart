part of 'ledger_store.dart';

extension AccountSession on LedgerSession {
  Future<CommitResult> renameAccount(
    OperationKey operation,
    PublicId accountId,
    int expectedVersion,
    String name,
  ) => _mutateAccount(
    operation,
    accountId,
    () => FinancialWorkflows(_db).renameAccount(
      operation.workspace,
      accountId,
      expectedVersion,
      operation.operation,
      name,
    ),
  );

  Future<CommitResult> setAccountNetWorthInclusion(
    OperationKey operation,
    PublicId accountId,
    int expectedVersion,
    bool included,
  ) => _mutateAccount(
    operation,
    accountId,
    () => FinancialWorkflows(_db).setAccountNetWorthInclusion(
      operation.workspace,
      accountId,
      expectedVersion,
      operation.operation,
      included,
    ),
  );

  Future<CommitResult> archiveAccount(
    OperationKey operation,
    PublicId accountId,
    int expectedVersion,
  ) => _mutateAccount(
    operation,
    accountId,
    () => FinancialWorkflows(_db).archive(
      operation.workspace,
      accountId,
      expectedVersion,
      operation.operation,
    ),
  );

  Future<CommitResult> reactivateAccount(
    OperationKey operation,
    PublicId accountId,
    int expectedVersion,
  ) => _mutateAccount(
    operation,
    accountId,
    () => FinancialWorkflows(_db).reactivateAccount(
      operation.workspace,
      accountId,
      expectedVersion,
      operation.operation,
    ),
  );

  Future<CommitResult> closeAccount(
    OperationKey operation,
    PublicId accountId,
    int expectedVersion, {
    required BusinessDate date,
    required String reason,
    PublicId? successorId,
  }) => _mutateAccount(
    operation,
    accountId,
    () => FinancialWorkflows(_db).closeAccount(
      operation.workspace,
      accountId,
      expectedVersion,
      operation.operation,
      date: date,
      reason: reason,
      successorId: successorId,
    ),
  );

  Future<CommitResult> _mutateAccount(
    OperationKey operation,
    PublicId accountId,
    Future<CommitResult> Function() mutation,
  ) => _enqueue(
    () => _write(() async {
      if (!await _hasOperation(operation)) {
        await _admitCapacity();
        await _checkRows('accounts', 'workspace=? AND id=?', [
          operation.workspace.toString(),
          accountId.value,
        ], remove: true);
      }
      final result = await mutation();
      if (!result.replayed) {
        await _checkRows('accounts', 'workspace=? AND id=?', [
          operation.workspace.toString(),
          accountId.value,
        ]);
        await _checkOperationRows(operation);
      }
      return result;
    }),
  );
}
