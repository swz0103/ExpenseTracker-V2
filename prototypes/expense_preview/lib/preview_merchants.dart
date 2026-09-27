part of 'preview_engine.dart';

extension PreviewMerchants on PreviewEngine {
  Future<MerchantCatalog> merchants() => _exclusive((epoch) async {
    _require();
    final result = await _session!.merchants(_workspace!);
    _check(epoch);
    return result;
  });

  Future<SavedMerchantReference?> merchantFor(PublicId event) =>
      _exclusive((epoch) async {
        _require();
        final rows = await _session!.merchantFor(workspace, event);
        _check(epoch);
        return rows;
      });

  Future<void> createMerchant(
    OperationKey operation,
    PublicId id,
    String name,
  ) => _merchantCommand(
    operation,
    (session) => session.createMerchant(operation, id, name),
  );

  Future<void> renameMerchant(
    OperationKey operation,
    Merchant merchant,
    String name,
  ) => _merchantCommand(operation, (session) {
    if (merchant.workspace != operation.workspace) throw PreviewInvalid();
    return session.renameMerchant(
      operation,
      merchant.id,
      merchant.version,
      name,
    );
  });

  Future<void> archiveMerchant(
    OperationKey operation,
    Merchant merchant, {
    required bool archived,
  }) => _merchantCommand(operation, (session) {
    if (merchant.workspace != operation.workspace) throw PreviewInvalid();
    return session.archiveMerchant(
      operation,
      merchant.id,
      merchant.version,
      archived: archived,
    );
  });

  Future<void> mergeMerchant(
    OperationKey operation,
    Merchant source,
    Merchant target,
  ) => _merchantCommand(operation, (session) {
    if (source.workspace != operation.workspace ||
        target.workspace != operation.workspace) {
      throw PreviewInvalid();
    }
    return session.mergeMerchant(
      operation,
      sourceId: source.id,
      expectedSourceVersion: source.version,
      targetId: target.id,
      expectedTargetVersion: target.version,
    );
  });

  Future<void> changeMerchantAlias(
    OperationKey operation,
    Merchant merchant,
    String alias, {
    required bool remove,
  }) => _merchantCommand(operation, (session) {
    if (merchant.workspace != operation.workspace) throw PreviewInvalid();
    return session.changeMerchantAlias(
      operation,
      merchant.id,
      merchant.version,
      alias,
      remove: remove,
    );
  });

  Future<void> _merchantCommand(
    OperationKey operation,
    Future<Object?> Function(LedgerSession) work,
  ) => _exclusive((epoch) async {
    _require();
    if (operation.workspace != _workspace) throw PreviewInvalid();
    await work(_session!);
    _check(epoch);
  });
}
