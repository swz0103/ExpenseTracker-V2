part of 'ledger_store.dart';

/// Merchants commands share the revocable session, queue and transaction scope.
/// Callers use business values without receiving a database or data adapter.
extension MerchantSession on LedgerSession {
  void _merchantsEnabled() {
    if (!_db.merchantsAware)
      throw UnsupportedError('Merchants are not enabled.');
  }

  Future<MerchantCatalog> merchants(WorkspaceId workspace) => _enqueue(() {
    _merchantsEnabled();
    return MerchantsAdapter(_db).read(workspace);
  });

  Future<CommitResult> createMerchant(
    OperationKey operation,
    PublicId id,
    String name,
  ) => _mutateMerchant(operation, MerchantMutation.create(id, name));

  Future<CommitResult> renameMerchant(
    OperationKey operation,
    PublicId id,
    int expectedVersion,
    String name,
  ) => _mutateMerchant(
    operation,
    MerchantMutation.rename(id, expectedVersion, name),
  );

  Future<CommitResult> archiveMerchant(
    OperationKey operation,
    PublicId id,
    int expectedVersion, {
    required bool archived,
  }) => _mutateMerchant(
    operation,
    MerchantMutation.archive(id, expectedVersion, archived),
  );

  Future<CommitResult> mergeMerchant(
    OperationKey operation, {
    required PublicId sourceId,
    required int expectedSourceVersion,
    required PublicId targetId,
    required int expectedTargetVersion,
  }) => _mutateMerchant(
    operation,
    MerchantMutation.merge(
      sourceId,
      expectedSourceVersion,
      targetId,
      expectedTargetVersion,
    ),
  );

  Future<CommitResult> changeMerchantAlias(
    OperationKey operation,
    PublicId id,
    int expectedVersion,
    String alias, {
    required bool remove,
  }) => _mutateMerchant(
    operation,
    MerchantMutation.alias(id, expectedVersion, alias, remove: remove),
  );

  Future<CommitResult> _mutateMerchant(
    OperationKey operation,
    MerchantMutation mutation,
  ) => _enqueue(
    () => _write(() async {
      _merchantsEnabled();
      if (!await _hasOperation(operation)) {
        await _admitCapacity();
        if (await _count('merchant_changes') >=
                LedgerSession.maxMerchantChanges ||
            (mutation.input[1] == 'create' &&
                await _count('merchants') >= LedgerSession.maxMerchants)) {
          throw PreviewCapacity();
        }
        // Only the selected merchant row is updated by these commands.
        // Subtract it before charging the replacement and new history/receipt.
        await _checkRows('merchants', 'workspace=? AND id=?', [
          operation.workspace.toString(),
          mutation.id.value,
        ], remove: true);
      }
      final result = await MerchantsAdapter(_db).mutate(operation, mutation);
      if (!result.replayed) {
        final ws = operation.workspace.toString();
        await _checkRows('merchants', 'workspace=? AND id=?', [
          ws,
          mutation.id.value,
        ]);
        await _checkRows('merchant_changes', 'workspace=? AND operation_id=?', [
          ws,
          operation.operation.toString(),
        ]);
        await _checkOperationRows(operation);
      }
      return result;
    }),
  );
}
