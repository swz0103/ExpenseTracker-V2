part of 'ledger_store.dart';

/// Categories commands share the revocable session, queue and transaction scope.
/// Callers use business values without receiving a database or data adapter.
extension CategorySession on LedgerSession {
  void _categoriesEnabled() {
    if (!_db.categoryAware)
      throw UnsupportedError('Categories are not enabled.');
  }

  Future<CategoryCatalog> categories(WorkspaceId workspace) => _enqueue(() {
    _categoriesEnabled();
    return CategoriesAdapter(_db).read(workspace);
  });

  Future<CommitResult> createCategory(
    OperationKey operation,
    PublicId id,
    String name,
    CategoryKind kind, {
    PublicId? parentId,
  }) => _mutateCategory(
    operation,
    CategoryMutation.create(id, name, kind, parentId: parentId),
  );

  Future<CommitResult> renameCategory(
    OperationKey operation,
    PublicId id,
    int expectedVersion,
    String name,
  ) => _mutateCategory(
    operation,
    CategoryMutation.rename(id, expectedVersion, name),
  );

  Future<CommitResult> moveCategory(
    OperationKey operation,
    PublicId id,
    int expectedVersion,
    PublicId? parentId,
  ) => _mutateCategory(
    operation,
    CategoryMutation.move(id, expectedVersion, parentId),
  );

  Future<CommitResult> archiveCategory(
    OperationKey operation,
    PublicId id,
    int expectedVersion, {
    required bool archived,
  }) => _mutateCategory(
    operation,
    CategoryMutation.archive(id, expectedVersion, archived),
  );

  Future<CommitResult> mergeCategory(
    OperationKey operation, {
    required PublicId sourceId,
    required int expectedSourceVersion,
    required PublicId targetId,
    required int expectedTargetVersion,
  }) => _mutateCategory(
    operation,
    CategoryMutation.merge(
      sourceId,
      expectedSourceVersion,
      targetId,
      expectedTargetVersion,
    ),
  );

  Future<CommitResult> _mutateCategory(
    OperationKey operation,
    CategoryMutation mutation,
  ) => _enqueue(
    () => _db.transaction(() async {
      _categoriesEnabled();
      if (!await _hasOperation(operation)) {
        await _admitCapacity();
        if (await _count('category_changes') >=
                LedgerSession.maxCategoryChanges ||
            (mutation.input[1] == 'create' &&
                await _count('categories') >= LedgerSession.maxCategories)) {
          throw PreviewCapacity();
        }
      }
      final result = await CategoriesAdapter(_db).mutate(operation, mutation);
      if (!result.replayed) {
        final ws = operation.workspace.toString();
        await _checkRows('categories', 'workspace=? AND id=?', [
          ws,
          mutation.id.value,
        ]);
        await _checkRows('category_changes', 'workspace=? AND operation_id=?', [
          ws,
          operation.operation.toString(),
        ]);
        await _checkOperationRows(operation);
      }
      return result;
    }),
  );
}
