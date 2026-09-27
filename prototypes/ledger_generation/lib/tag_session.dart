part of 'ledger_store.dart';

/// Tags commands share the revocable session, queue and transaction scope.
/// Callers use business values without receiving a database or data adapter.
extension TagSession on LedgerSession {
  void _tagsEnabled() {
    if (!_db.tagsAware) throw UnsupportedError('Tags are not enabled.');
  }

  Future<TagCatalog> tags(WorkspaceId workspace) => _enqueue(() {
    _tagsEnabled();
    return TagsAdapter(_db).read(workspace);
  });

  Future<CommitResult> createTag(
    OperationKey operation,
    PublicId id,
    String name,
  ) => _mutateTag(operation, TagMutation.create(id, name));

  Future<CommitResult> renameTag(
    OperationKey operation,
    PublicId id,
    int expectedVersion,
    String name,
  ) => _mutateTag(operation, TagMutation.rename(id, expectedVersion, name));

  Future<CommitResult> archiveTag(
    OperationKey operation,
    PublicId id,
    int expectedVersion, {
    required bool archived,
  }) =>
      _mutateTag(operation, TagMutation.archive(id, expectedVersion, archived));

  Future<CommitResult> mergeTag(
    OperationKey operation, {
    required PublicId sourceId,
    required int expectedSourceVersion,
    required PublicId targetId,
    required int expectedTargetVersion,
  }) => _mutateTag(
    operation,
    TagMutation.merge(
      sourceId,
      expectedSourceVersion,
      targetId,
      expectedTargetVersion,
    ),
  );

  Future<CommitResult> _mutateTag(
    OperationKey operation,
    TagMutation mutation,
  ) => _enqueue(
    () => _write(() async {
      _tagsEnabled();
      if (!await _hasOperation(operation)) {
        await _admitCapacity();
        if (await _count('tag_changes') >= LedgerSession.maxTagChanges ||
            (mutation.input[1] == 'create' &&
                await _count('tags') >= LedgerSession.maxTags)) {
          throw PreviewCapacity();
        }
        // Only the selected tag row is updated by these commands.
        // Subtract it before charging the replacement and new history/receipt.
        await _checkRows('tags', 'workspace=? AND id=?', [
          operation.workspace.toString(),
          mutation.id.value,
        ], remove: true);
      }
      final result = await TagsAdapter(_db).mutate(operation, mutation);
      if (!result.replayed) {
        final ws = operation.workspace.toString();
        await _checkRows('tags', 'workspace=? AND id=?', [
          ws,
          mutation.id.value,
        ]);
        await _checkRows('tag_changes', 'workspace=? AND operation_id=?', [
          ws,
          operation.operation.toString(),
        ]);
        await _checkOperationRows(operation);
      }
      return result;
    }),
  );
}
