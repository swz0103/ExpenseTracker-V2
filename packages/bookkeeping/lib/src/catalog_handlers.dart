part of 'bookkeeping.dart';

/// Categories, tags and merchants.
extension _Catalogs<T extends BookkeepingTransaction> on Bookkeeping<T> {
  Future<int> _catalog(T t, ChangeCatalog command) async {
    final workspace = command.operation.workspace;
    final change = command.change;
    switch (command.catalog) {
      case CatalogType.category:
        final before = await t.categories(workspace);
        final catalog = CategoryCatalog.restore(workspace, before);
        final after = _changeCategories(catalog, workspace, change).categories;
        return _commitCatalog(
          t,
          before: {for (final row in before) row.id: row.version},
          after: {for (final row in after) row.id: (row, row.version)},
          subject: change.subject,
          workspace: workspace,
          save: t.saveCategory,
          encode: CatalogCodec.category,
          kind: 'category.changed',
        );
      case CatalogType.tag:
        final before = await t.tags(workspace);
        final catalog = TagCatalog.restore(workspace, before);
        final after = _changeTags(catalog, workspace, change).tags;
        return _commitCatalog(
          t,
          before: {for (final row in before) row.id: row.version},
          after: {for (final row in after) row.id: (row, row.version)},
          subject: change.subject,
          workspace: workspace,
          save: t.saveTag,
          encode: CatalogCodec.tag,
          kind: 'tag.changed',
        );
      case CatalogType.merchant:
        final before = await t.merchants(workspace);
        final catalog = MerchantCatalog.restore(workspace, before);
        final after = _changeMerchants(catalog, workspace, change).merchants;
        return _commitCatalog(
          t,
          before: {for (final row in before) row.id: row.version},
          after: {for (final row in after) row.id: (row, row.version)},
          subject: change.subject,
          workspace: workspace,
          save: t.saveMerchant,
          encode: CatalogCodec.merchant,
          kind: 'merchant.changed',
        );
    }
  }

  /// Saves and journals every row whose version moved.
  Future<int> _commitCatalog<R>(
    T t, {
    required Map<PublicId, int> before,
    required Map<PublicId, (R, int)> after,
    required PublicId subject,
    required WorkspaceId workspace,
    required Future<void> Function(R row) save,
    required Map<String, Object?> Function(R row) encode,
    required String kind,
  }) async {
    for (final entry in after.entries) {
      final (row, version) = entry.value;
      if (before[entry.key] == version) continue;
      await save(row);
      await t.appendEvent(
        id: PublicId.generate(),
        workspace: workspace,
        kind: kind,
        payload: jsonEncode(encode(row)),
      );
    }
    return after[subject]!.$2;
  }
}
