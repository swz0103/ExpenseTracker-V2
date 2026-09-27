part of 'preview_engine.dart';

extension PreviewCategories on PreviewEngine {
  Future<CategoryCatalog> categories() => _exclusive((epoch) async {
    _require();
    final result = await _session!.categories(_workspace!);
    _check(epoch);
    return result;
  });

  Future<List<LedgerAllocation>> allocations(PublicId eventId) =>
      _exclusive((epoch) async {
        _require();
        final result = await _session!.allocations(_workspace!, eventId);
        _check(epoch);
        return result;
      });

  Future<void> createCategory(
    OperationKey operation,
    PublicId id,
    String name,
    CategoryKind kind, {
    PublicId? parentId,
  }) => _categoryCommand(
    operation,
    (session) =>
        session.createCategory(operation, id, name, kind, parentId: parentId),
  );

  Future<void> renameCategory(
    OperationKey operation,
    Category category,
    String name,
  ) => _categoryCommand(operation, (session) {
    if (category.workspace != operation.workspace) throw PreviewInvalid();
    return session.renameCategory(
      operation,
      category.id,
      category.version,
      name,
    );
  });

  Future<void> archiveCategory(
    OperationKey operation,
    Category category, {
    required bool archived,
  }) => _categoryCommand(operation, (session) {
    if (category.workspace != operation.workspace) throw PreviewInvalid();
    return session.archiveCategory(
      operation,
      category.id,
      category.version,
      archived: archived,
    );
  });

  Future<void> moveCategory(
    OperationKey operation,
    Category category,
    PublicId? parentId,
  ) => _categoryCommand(operation, (session) {
    if (category.workspace != operation.workspace) throw PreviewInvalid();
    return session.moveCategory(
      operation,
      category.id,
      category.version,
      parentId,
    );
  });

  Future<void> mergeCategory(
    OperationKey operation,
    Category source,
    Category target,
  ) => _categoryCommand(operation, (session) {
    if (source.workspace != operation.workspace ||
        target.workspace != operation.workspace) {
      throw PreviewInvalid();
    }
    return session.mergeCategory(
      operation,
      sourceId: source.id,
      expectedSourceVersion: source.version,
      targetId: target.id,
      expectedTargetVersion: target.version,
    );
  });

  Future<void> _categoryCommand(
    OperationKey operation,
    Future<Object?> Function(LedgerSession) work,
  ) => _exclusive((epoch) async {
    _require();
    if (operation.workspace != _workspace) throw PreviewInvalid();
    await work(_session!);
    _check(epoch);
  });
}
