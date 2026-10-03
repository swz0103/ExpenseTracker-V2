import 'package:foundation_values/foundation_values.dart';

enum MerchantError {
  invalidInput,
  workspaceMismatch,
  versionConflict,
  missing,
  duplicate,
  unavailable,
  replacementCycle,
}

final class MerchantException implements Exception {
  const MerchantException(this.code);
  final MerchantError code;
  @override
  String toString() => 'MerchantException(${code.name})';
}

/// Immutable identity and metadata, never a financial amount or transaction.
final class Merchant {
  Merchant.restore({
    required this.id,
    required this.workspace,
    required String name,
    required this.version,
    this.archived = false,
    this.replacementId,
    Iterable<String> aliases = const [],
  }) : name = _name(name),
       aliases = _aliases(aliases) {
    if (version < 1 ||
        replacementId == id ||
        (replacementId != null && !archived)) {
      throw const MerchantException(MerchantError.invalidInput);
    }
    // addAlias refuses an alias equal to the name; restore must agree.
    if (aliases.any((alias) => _key(alias) == _key(this.name))) {
      throw const MerchantException(MerchantError.duplicate);
    }
  }

  final PublicId id;
  final WorkspaceId workspace;
  final String name;
  final List<String> aliases;
  final int version;
  final bool archived;
  final PublicId? replacementId;
}

/// A validated workspace view. Application must load/check/write the affected
/// rows and Audit in one UoW; this value does not provide persistence or CAS.
final class MerchantCatalog {
  factory MerchantCatalog.empty(WorkspaceId workspace) =>
      MerchantCatalog.restore(workspace, const []);

  factory MerchantCatalog.restore(
    WorkspaceId workspace,
    Iterable<Merchant> merchants,
  ) {
    final rows = <PublicId, Merchant>{};
    for (final row in merchants) {
      if (row.workspace != workspace) {
        throw const MerchantException(MerchantError.workspaceMismatch);
      }
      if (rows.containsKey(row.id)) {
        throw const MerchantException(MerchantError.duplicate);
      }
      rows[row.id] = row;
    }
    for (final row in rows.values) {
      final successor = row.replacementId;
      if (successor != null) {
        final target = rows[successor];
        if (target == null)
          throw const MerchantException(MerchantError.missing);
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
          throw const MerchantException(MerchantError.replacementCycle);
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
    return MerchantCatalog._(
      workspace,
      Map.unmodifiable(rows),
      Map.unmodifiable(canonical),
    );
  }

  MerchantCatalog._(this.workspace, this._rows, this._canonical);
  final WorkspaceId workspace;
  final Map<PublicId, Merchant> _rows;
  final Map<PublicId, PublicId> _canonical;
  List<Merchant> get merchants => List.unmodifiable(_rows.values);

  Merchant get(PublicId id) =>
      _rows[id] ?? (throw const MerchantException(MerchantError.missing));

  /// Historical views can display both the original and canonical merchant.
  /// Archived canonical merchants remain readable, but cannot be selected.
  Merchant resolve(PublicId id) {
    get(id);
    return _rows[_canonical[id]]!;
  }

  /// Suggestions only. Matching preserves punctuation and internal spacing,
  /// uses case-insensitive exact names/aliases, and never picks or merges.
  /// Old names/aliases on an explicit merge redirect to the live canonical ID.
  List<Merchant> candidates(String label) {
    if (label.trim().isEmpty) return const [];
    final key = _key(_name(label));
    final found = <PublicId, Merchant>{};
    for (final row in _rows.values) {
      if (row.archived && row.replacementId == null) continue;
      final canonical = resolve(row.id);
      if (canonical.archived) continue;
      if (_key(row.name) == key || row.aliases.any((a) => _key(a) == key)) {
        found[canonical.id] = canonical;
      }
    }
    final result = found.values.toList()
      ..sort((a, b) => a.id.value.compareTo(b.id.value));
    return List.unmodifiable(result);
  }

  MerchantCatalog addAlias({
    required WorkspaceId workspace,
    required PublicId id,
    required int expectedVersion,
    required String alias,
  }) {
    final row = _mutable(workspace, id, expectedVersion);
    final value = _name(alias), key = _key(alias);
    if (_key(row.name) == key || row.aliases.any((a) => _key(a) == key)) {
      throw const MerchantException(MerchantError.duplicate);
    }
    return _change(row, aliases: [...row.aliases, value]);
  }

  MerchantCatalog removeAlias({
    required WorkspaceId workspace,
    required PublicId id,
    required int expectedVersion,
    required String alias,
  }) {
    final row = _mutable(workspace, id, expectedVersion);
    final key = _key(_name(alias));
    if (!row.aliases.any((a) => _key(a) == key)) {
      throw const MerchantException(MerchantError.missing);
    }
    return _change(row, aliases: row.aliases.where((a) => _key(a) != key));
  }

  void requireSelection({
    required WorkspaceId workspace,
    required PublicId id,
    required int expectedVersion,
  }) {
    final row = _check(workspace, id, expectedVersion);
    _active(row);
  }

  MerchantCatalog create({
    required WorkspaceId workspace,
    required PublicId id,
    required String name,
  }) {
    _workspace(workspace);
    if (_rows.containsKey(id)) {
      throw const MerchantException(MerchantError.duplicate);
    }
    return _replace(
      Merchant.restore(id: id, workspace: workspace, name: name, version: 1),
    );
  }

  MerchantCatalog rename({
    required WorkspaceId workspace,
    required PublicId id,
    required int expectedVersion,
    required String name,
  }) {
    final row = _mutable(workspace, id, expectedVersion);
    return _change(row, name: name);
  }

  MerchantCatalog setArchived({
    required WorkspaceId workspace,
    required PublicId id,
    required int expectedVersion,
    required bool archived,
  }) {
    final row = _mutable(workspace, id, expectedVersion);
    if (row.archived == archived) {
      throw const MerchantException(MerchantError.unavailable);
    }
    return _change(row, archived: archived);
  }

  /// Explicit redirect, preserving the original entity and historical IDs.
  MerchantCatalog merge({
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
      throw const MerchantException(MerchantError.invalidInput);
    }
    return _change(source, archived: true, replacementId: targetId);
  }

  void _workspace(WorkspaceId workspace) {
    if (workspace != this.workspace) {
      throw const MerchantException(MerchantError.workspaceMismatch);
    }
  }

  Merchant _check(WorkspaceId workspace, PublicId id, int expectedVersion) {
    _workspace(workspace);
    final row = get(id);
    if (row.version != expectedVersion) {
      throw const MerchantException(MerchantError.versionConflict);
    }
    return row;
  }

  Merchant _mutable(WorkspaceId workspace, PublicId id, int expectedVersion) {
    final row = _check(workspace, id, expectedVersion);
    if (row.version >= _maxSafeVersion) {
      throw const MerchantException(MerchantError.versionConflict);
    }
    if (row.replacementId != null) {
      throw const MerchantException(MerchantError.unavailable);
    }
    return row;
  }

  void _active(Merchant row) {
    if (row.archived || row.replacementId != null) {
      throw const MerchantException(MerchantError.unavailable);
    }
  }

  MerchantCatalog _change(
    Merchant row, {
    String? name,
    Iterable<String>? aliases,
    bool? archived,
    PublicId? replacementId,
  }) => _replace(
    Merchant.restore(
      id: row.id,
      workspace: row.workspace,
      name: name ?? row.name,
      aliases: aliases ?? row.aliases,
      version: row.version + 1,
      archived: archived ?? row.archived,
      replacementId: replacementId ?? row.replacementId,
    ),
  );

  MerchantCatalog _replace(Merchant row) =>
      MerchantCatalog.restore(workspace, {..._rows, row.id: row}.values);
}

String _name(String value) {
  final result = cleanName(value);
  if (result == null) throw const MerchantException(MerchantError.invalidInput);
  return result;
}

String _key(String value) => nameKey(value);

List<String> _aliases(Iterable<String> input) {
  final values = input.map(_name).toList();
  if (values.length > 16) {
    throw const MerchantException(MerchantError.invalidInput);
  }
  final keys = <String>{};
  for (final value in values) {
    if (!keys.add(_key(value))) {
      throw const MerchantException(MerchantError.duplicate);
    }
  }
  values.sort((a, b) => _key(a).compareTo(_key(b)));
  return List.unmodifiable(values);
}

/// The largest version that can still be incremented exactly on every
/// platform, including the web, where integers are doubles.
const _maxSafeVersion = 9007199254740991;
