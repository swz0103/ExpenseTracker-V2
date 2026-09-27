part of 'preview_engine.dart';

extension PreviewTags on PreviewEngine {
  Future<TagCatalog> tags() => _exclusive((epoch) async {
    _require();
    final result = await _session!.tags(_workspace!);
    _check(epoch);
    return result;
  });

  Future<List<SavedTagReference>> tagsFor(PublicId event) =>
      _exclusive((epoch) async {
        _require();
        final rows = await _session!.tagsFor(workspace, event);
        _check(epoch);
        return rows;
      });

  Future<void> createTag(OperationKey operation, PublicId id, String name) =>
      _tagCommand(
        operation,
        (session) => session.createTag(operation, id, name),
      );

  Future<void> renameTag(OperationKey operation, Tag tag, String name) =>
      _tagCommand(operation, (session) {
        if (tag.workspace != operation.workspace) throw PreviewInvalid();
        return session.renameTag(operation, tag.id, tag.version, name);
      });

  Future<void> archiveTag(
    OperationKey operation,
    Tag tag, {
    required bool archived,
  }) => _tagCommand(operation, (session) {
    if (tag.workspace != operation.workspace) throw PreviewInvalid();
    return session.archiveTag(
      operation,
      tag.id,
      tag.version,
      archived: archived,
    );
  });

  Future<void> mergeTag(OperationKey operation, Tag source, Tag target) =>
      _tagCommand(operation, (session) {
        if (source.workspace != operation.workspace ||
            target.workspace != operation.workspace) {
          throw PreviewInvalid();
        }
        return session.mergeTag(
          operation,
          sourceId: source.id,
          expectedSourceVersion: source.version,
          targetId: target.id,
          expectedTargetVersion: target.version,
        );
      });

  Future<void> _tagCommand(
    OperationKey operation,
    Future<Object?> Function(LedgerSession) work,
  ) => _exclusive((epoch) async {
    _require();
    if (operation.workspace != _workspace) throw PreviewInvalid();
    await work(_session!);
    _check(epoch);
  });
}
