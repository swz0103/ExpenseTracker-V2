import 'package:foundation_values/foundation_values.dart';

enum CategoryKind { income, expense }

enum CategoryError {
  invalidInput,
  workspaceMismatch,
  versionConflict,
  missing,
  duplicate,
  kindMismatch,
  invalidHierarchy,
  unavailable,
  hasChildren,
  replacementCycle,
}

final class CategoryException implements Exception {
  const CategoryException(this.code);
  final CategoryError code;
  @override
  String toString() => 'CategoryException(${code.name})';
}

/// Immutable identity and metadata, never a financial amount or transaction.
final class Category {
  Category.restore({
    required this.id,
    required this.workspace,
    required String name,
    required this.kind,
    required this.version,
    this.parentId,
    this.archived = false,
    this.replacementId,
  }) : name = _name(name) {
    if (version < 1 ||
        parentId == id ||
        replacementId == id ||
        (replacementId != null && !archived)) {
      throw const CategoryException(CategoryError.invalidInput);
    }
  }

  final PublicId id;
  final WorkspaceId workspace;
  final String name;
  final CategoryKind kind;
  final int version;
  final PublicId? parentId;
  final bool archived;
  final PublicId? replacementId;
}

/// A validated workspace view. Application must load/check/write the affected
/// rows and Audit in one UoW; this value does not provide persistence or CAS.
final class CategoryCatalog {
  factory CategoryCatalog.empty(WorkspaceId workspace) =>
      CategoryCatalog.restore(workspace, const []);

  factory CategoryCatalog.restore(
    WorkspaceId workspace,
    Iterable<Category> categories,
  ) {
    final rows = <PublicId, Category>{};
    for (final row in categories) {
      if (row.workspace != workspace) {
        throw const CategoryException(CategoryError.workspaceMismatch);
      }
      if (rows.containsKey(row.id)) {
        throw const CategoryException(CategoryError.duplicate);
      }
      rows[row.id] = row;
    }
    for (final row in rows.values) {
      final parentId = row.parentId;
      if (parentId != null) {
        final parent = rows[parentId];
        if (parent == null ||
            parent.parentId != null ||
            parent.replacementId != null) {
          throw const CategoryException(CategoryError.invalidHierarchy);
        }
        if (parent.kind != row.kind) {
          throw const CategoryException(CategoryError.kindMismatch);
        }
        if (!row.archived && parent.archived) {
          throw const CategoryException(CategoryError.unavailable);
        }
      }
      final successor = row.replacementId;
      if (successor != null) {
        final target = rows[successor];
        if (target == null)
          throw const CategoryException(CategoryError.missing);
        if (target.kind != row.kind) {
          throw const CategoryException(CategoryError.kindMismatch);
        }
      }
    }
    // Resolve all chains iteratively in O(n), including an untrusted long
    // history. The derived index is disposable and never changes saved IDs.
    final canonical = <PublicId, PublicId>{};
    for (final id in rows.keys) {
      if (canonical.containsKey(id)) continue;
      final path = <PublicId>{};
      var cursor = id;
      while (!canonical.containsKey(cursor)) {
        if (!path.add(cursor)) {
          throw const CategoryException(CategoryError.replacementCycle);
        }
        final next = rows[cursor]!.replacementId;
        if (next == null) {
          canonical[cursor] = cursor;
          break;
        }
        cursor = next;
      }
      final resolved = canonical[cursor]!;
      for (final member in path) {
        canonical[member] = resolved;
      }
    }
    return CategoryCatalog._(
      workspace,
      Map.unmodifiable(rows),
      Map.unmodifiable(canonical),
    );
  }

  CategoryCatalog._(this.workspace, this._rows, this._canonical);
  final WorkspaceId workspace;
  final Map<PublicId, Category> _rows;
  final Map<PublicId, PublicId> _canonical;
  List<Category> get categories => List.unmodifiable(_rows.values);

  Category get(PublicId id) =>
      _rows[id] ?? (throw const CategoryException(CategoryError.missing));

  /// Historical views can display both the original and canonical category.
  /// Archived canonical categories remain readable, but cannot be selected.
  Category resolve(PublicId id) {
    get(id);
    return _rows[_canonical[id]]!;
  }

  void requireSelection({
    required WorkspaceId workspace,
    required PublicId id,
    required CategoryKind kind,
    required int expectedVersion,
  }) {
    final row = _check(workspace, id, expectedVersion);
    _active(row);
    if (row.kind != kind) {
      throw const CategoryException(CategoryError.kindMismatch);
    }
  }

  CategoryCatalog create({
    required WorkspaceId workspace,
    required PublicId id,
    required String name,
    required CategoryKind kind,
    PublicId? parentId,
  }) {
    _workspace(workspace);
    if (_rows.containsKey(id)) {
      throw const CategoryException(CategoryError.duplicate);
    }
    return _replace(
      Category.restore(
        id: id,
        workspace: workspace,
        name: name,
        kind: kind,
        version: 1,
        parentId: parentId,
      ),
    );
  }

  CategoryCatalog rename({
    required WorkspaceId workspace,
    required PublicId id,
    required int expectedVersion,
    required String name,
  }) {
    final row = _mutable(workspace, id, expectedVersion);
    return _change(row, name: name);
  }

  /// Moving a parent with any historical children would create a third level.
  /// Pass null to promote a child; kind and identity are immutable.
  CategoryCatalog move({
    required WorkspaceId workspace,
    required PublicId id,
    required int expectedVersion,
    required PublicId? parentId,
  }) {
    final row = _mutable(workspace, id, expectedVersion);
    _active(row);
    return _replace(
      Category.restore(
        id: row.id,
        workspace: row.workspace,
        name: row.name,
        kind: row.kind,
        version: row.version + 1,
        parentId: parentId,
      ),
    );
  }

  CategoryCatalog setArchived({
    required WorkspaceId workspace,
    required PublicId id,
    required int expectedVersion,
    required bool archived,
  }) {
    final row = _mutable(workspace, id, expectedVersion);
    if (row.archived == archived) {
      throw const CategoryException(CategoryError.unavailable);
    }
    if (archived && _rows.values.any((c) => c.parentId == id && !c.archived)) {
      throw const CategoryException(CategoryError.hasChildren);
    }
    return _change(row, archived: archived);
  }

  /// Explicit redirect, preserving the original entity and historical IDs.
  /// Parent categories with children require an explicit child migration first.
  CategoryCatalog merge({
    required WorkspaceId workspace,
    required PublicId sourceId,
    required int expectedSourceVersion,
    required PublicId targetId,
    required int expectedTargetVersion,
  }) {
    final source = _mutable(workspace, sourceId, expectedSourceVersion);
    final target = _check(workspace, targetId, expectedTargetVersion);
    _active(target);
    if (sourceId == targetId) {
      throw const CategoryException(CategoryError.invalidInput);
    }
    if (source.kind != target.kind) {
      throw const CategoryException(CategoryError.kindMismatch);
    }
    if (_rows.values.any((c) => c.parentId == sourceId)) {
      throw const CategoryException(CategoryError.hasChildren);
    }
    return _change(source, archived: true, replacementId: targetId);
  }

  void _workspace(WorkspaceId workspace) {
    if (workspace != this.workspace) {
      throw const CategoryException(CategoryError.workspaceMismatch);
    }
  }

  Category _check(WorkspaceId workspace, PublicId id, int expectedVersion) {
    _workspace(workspace);
    final row = get(id);
    if (row.version != expectedVersion) {
      throw const CategoryException(CategoryError.versionConflict);
    }
    return row;
  }

  Category _mutable(WorkspaceId workspace, PublicId id, int expectedVersion) {
    final row = _check(workspace, id, expectedVersion);
    if (row.version == 9223372036854775807) {
      throw const CategoryException(CategoryError.versionConflict);
    }
    if (row.replacementId != null) {
      throw const CategoryException(CategoryError.unavailable);
    }
    return row;
  }

  void _active(Category row) {
    if (row.archived || row.replacementId != null) {
      throw const CategoryException(CategoryError.unavailable);
    }
  }

  CategoryCatalog _change(
    Category row, {
    String? name,
    bool? archived,
    PublicId? replacementId,
  }) => _replace(
    Category.restore(
      id: row.id,
      workspace: row.workspace,
      name: name ?? row.name,
      kind: row.kind,
      version: row.version + 1,
      parentId: row.parentId,
      archived: archived ?? row.archived,
      replacementId: replacementId ?? row.replacementId,
    ),
  );

  CategoryCatalog _replace(Category row) =>
      CategoryCatalog.restore(workspace, {..._rows, row.id: row}.values);
}

String _name(String value) {
  final result = value.trim();
  if (result.isEmpty ||
      result.length > 100 ||
      RegExp(r'[\x00-\x1f\x7f]').hasMatch(result)) {
    throw const CategoryException(CategoryError.invalidInput);
  }
  return result;
}
