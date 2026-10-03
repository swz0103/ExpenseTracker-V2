import 'package:foundation_values/foundation_values.dart';

enum TagError {
  invalidInput,
  workspaceMismatch,
  versionConflict,
  missing,
  duplicate,
  unavailable,
  replacementCycle,
}

final class TagException implements Exception {
  const TagException(this.code);
  final TagError code;
  @override
  String toString() => 'TagException(${code.name})';
}

/// Immutable identity and metadata, never a financial amount or transaction.
final class Tag {
  Tag.restore({
    required this.id,
    required this.workspace,
    required String name,
    required this.version,
    this.archived = false,
    this.replacementId,
  }) : name = _name(name) {
    if (version < 1 ||
        replacementId == id ||
        (replacementId != null && !archived)) {
      throw const TagException(TagError.invalidInput);
    }
  }

  final PublicId id;
  final WorkspaceId workspace;
  final String name;
  final int version;
  final bool archived;
  final PublicId? replacementId;
}

/// A validated workspace view. Application must load/check/write the affected
/// rows and Audit in one UoW; this value does not provide persistence or CAS.
final class TagCatalog {
  factory TagCatalog.empty(WorkspaceId workspace) =>
      TagCatalog.restore(workspace, const []);

  factory TagCatalog.restore(WorkspaceId workspace, Iterable<Tag> tags) {
    final rows = <PublicId, Tag>{};
    for (final row in tags) {
      if (row.workspace != workspace) {
        throw const TagException(TagError.workspaceMismatch);
      }
      if (rows.containsKey(row.id)) {
        throw const TagException(TagError.duplicate);
      }
      rows[row.id] = row;
    }
    for (final row in rows.values) {
      final successor = row.replacementId;
      if (successor != null) {
        final target = rows[successor];
        if (target == null) throw const TagException(TagError.missing);
      }
    }
    final canonical = resolveRedirects({
      for (final row in rows.values) row.id: row.replacementId,
    });
    if (canonical == null) throw const TagException(TagError.replacementCycle);
    return TagCatalog._(
      workspace,
      Map.unmodifiable(rows),
      Map.unmodifiable(canonical),
    );
  }

  TagCatalog._(this.workspace, this._rows, this._canonical);
  final WorkspaceId workspace;
  final Map<PublicId, Tag> _rows;
  final Map<PublicId, PublicId> _canonical;
  List<Tag> get tags => List.unmodifiable(_rows.values);

  Tag get(PublicId id) =>
      _rows[id] ?? (throw const TagException(TagError.missing));

  /// Historical views can display both the original and canonical tag.
  /// Archived canonical tags remain readable, but cannot be selected.
  Tag resolve(PublicId id) {
    get(id);
    return _rows[_canonical[id]]!;
  }

  void requireSelection({
    required WorkspaceId workspace,
    required PublicId id,
    required int expectedVersion,
  }) {
    final row = _check(workspace, id, expectedVersion);
    _active(row);
  }

  TagCatalog create({
    required WorkspaceId workspace,
    required PublicId id,
    required String name,
  }) {
    _workspace(workspace);
    if (_rows.containsKey(id)) {
      throw const TagException(TagError.duplicate);
    }
    _unique(id, name);
    return _replace(
      Tag.restore(id: id, workspace: workspace, name: name, version: 1),
    );
  }

  TagCatalog rename({
    required WorkspaceId workspace,
    required PublicId id,
    required int expectedVersion,
    required String name,
  }) {
    final row = _mutable(workspace, id, expectedVersion);
    _unique(id, name);
    return _change(row, name: name);
  }

  /// Two live tags with one name would split every report in two
  /// (feature audit G-19).
  void _unique(PublicId self, String name) {
    final key = nameKey(name);
    for (final row in _rows.values) {
      if (row.id != self &&
          row.replacementId == null &&
          nameKey(row.name) == key) {
        throw const TagException(TagError.duplicate);
      }
    }
  }

  TagCatalog setArchived({
    required WorkspaceId workspace,
    required PublicId id,
    required int expectedVersion,
    required bool archived,
  }) {
    final row = _mutable(workspace, id, expectedVersion);
    if (row.archived == archived) {
      throw const TagException(TagError.unavailable);
    }
    return _change(row, archived: archived);
  }

  /// Explicit redirect, preserving the original entity and historical IDs.
  TagCatalog merge({
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
      throw const TagException(TagError.invalidInput);
    }
    return _change(source, archived: true, replacementId: targetId);
  }

  void _workspace(WorkspaceId workspace) {
    if (workspace != this.workspace) {
      throw const TagException(TagError.workspaceMismatch);
    }
  }

  Tag _check(WorkspaceId workspace, PublicId id, int expectedVersion) {
    _workspace(workspace);
    final row = get(id);
    if (row.version != expectedVersion) {
      throw const TagException(TagError.versionConflict);
    }
    return row;
  }

  Tag _mutable(WorkspaceId workspace, PublicId id, int expectedVersion) {
    final row = _check(workspace, id, expectedVersion);
    if (row.version >= _maxSafeVersion) {
      throw const TagException(TagError.versionConflict);
    }
    if (row.replacementId != null) {
      throw const TagException(TagError.unavailable);
    }
    return row;
  }

  void _active(Tag row) {
    if (row.archived || row.replacementId != null) {
      throw const TagException(TagError.unavailable);
    }
  }

  TagCatalog _change(
    Tag row, {
    String? name,
    bool? archived,
    PublicId? replacementId,
  }) => _replace(
    Tag.restore(
      id: row.id,
      workspace: row.workspace,
      name: name ?? row.name,
      version: row.version + 1,
      archived: archived ?? row.archived,
      replacementId: replacementId ?? row.replacementId,
    ),
  );

  TagCatalog _replace(Tag row) =>
      TagCatalog.restore(workspace, {..._rows, row.id: row}.values);
}

String _name(String value) {
  final result = cleanName(value);
  if (result == null) throw const TagException(TagError.invalidInput);
  return result;
}

/// The largest version that can still be incremented exactly on every
/// platform, including the web, where integers are doubles.
const _maxSafeVersion = 9007199254740991;
