import 'dart:convert';

import 'package:categories/categories.dart';
import 'package:drift/drift.dart';
import 'package:foundation_values/foundation_values.dart';

import 'database.dart';
import 'operations.dart';

final class InvalidCategoryHistory implements Exception {
  const InvalidCategoryHistory();
  @override
  String toString() => 'InvalidCategoryHistory';
}

/// Versioned metadata command. Generated timestamps and result state are not
/// part of the retry key; public IDs and both merge revisions are retained.
final class CategoryMutation {
  CategoryMutation._(this.input);
  factory CategoryMutation.fromInput(Object? value) {
    if (value is! List) throw const InvalidCategoryHistory();
    final valid = switch (value) {
      ['category-v1', 'create', String _, String _, String _, String? _] =>
        true,
      ['category-v1', 'rename', String _, int _, String _] => true,
      ['category-v1', 'move', String _, int _, String? _] => true,
      ['category-v1', 'archive', String _, int _, bool _] => true,
      ['category-v1', 'merge', String _, int _, String _, int _] => true,
      _ => false,
    };
    if (!valid) throw const InvalidCategoryHistory();
    // Own an immutable copy, not the caller's mutable list.
    return CategoryMutation._(List<Object?>.unmodifiable(value));
  }
  factory CategoryMutation.create(
    PublicId id,
    String name,
    CategoryKind kind, {
    PublicId? parentId,
  }) => CategoryMutation.fromInput([
    'category-v1',
    'create',
    id.value,
    name.trim(),
    kind.name,
    parentId?.value,
  ]);
  factory CategoryMutation.rename(PublicId id, int version, String name) =>
      CategoryMutation.fromInput([
        'category-v1',
        'rename',
        id.value,
        version,
        name.trim(),
      ]);
  factory CategoryMutation.move(PublicId id, int version, PublicId? parentId) =>
      CategoryMutation.fromInput([
        'category-v1',
        'move',
        id.value,
        version,
        parentId?.value,
      ]);
  factory CategoryMutation.archive(PublicId id, int version, bool archived) =>
      CategoryMutation.fromInput([
        'category-v1',
        'archive',
        id.value,
        version,
        archived,
      ]);
  factory CategoryMutation.merge(
    PublicId id,
    int version,
    PublicId target,
    int targetVersion,
  ) => CategoryMutation.fromInput([
    'category-v1',
    'merge',
    id.value,
    version,
    target.value,
    targetVersion,
  ]);

  final List<Object?> input;
  PublicId get id => PublicId.parse(input[2] as String);
  String get auditKind => 'category.${input[1]}';
  CategoryCatalog apply(CategoryCatalog catalog) {
    final ws = catalog.workspace;
    return switch (input) {
      [
        'category-v1',
        'create',
        String _,
        String name,
        String kind,
        String? parent,
      ] =>
        catalog.create(
          workspace: ws,
          id: id,
          name: name,
          kind: CategoryKind.values.byName(kind),
          parentId: parent == null ? null : PublicId.parse(parent),
        ),
      ['category-v1', 'rename', String _, int version, String name] =>
        catalog.rename(
          workspace: ws,
          id: id,
          expectedVersion: version,
          name: name,
        ),
      ['category-v1', 'move', String _, int version, String? parent] =>
        catalog.move(
          workspace: ws,
          id: id,
          expectedVersion: version,
          parentId: parent == null ? null : PublicId.parse(parent),
        ),
      ['category-v1', 'archive', String _, int version, bool archived] =>
        catalog.setArchived(
          workspace: ws,
          id: id,
          expectedVersion: version,
          archived: archived,
        ),
      [
        'category-v1',
        'merge',
        String _,
        int version,
        String target,
        int targetVersion,
      ] =>
        catalog.merge(
          workspace: ws,
          sourceId: id,
          expectedSourceVersion: version,
          targetId: PublicId.parse(target),
          expectedTargetVersion: targetVersion,
        ),
      _ => throw const InvalidCategoryHistory(),
    };
  }
}

Map<String, Object?> categoryJson(Category category) => {
  'name': category.name,
  'kind': category.kind.name,
  'version': category.version,
  'parentId': category.parentId?.value,
  'archived': category.archived,
  'replacementId': category.replacementId?.value,
};

Category categoryFromJson(WorkspaceId workspace, PublicId id, String payload) {
  final value = jsonDecode(payload);
  if (value is! Map ||
      value.length != 6 ||
      ![
        'name',
        'kind',
        'version',
        'parentId',
        'archived',
        'replacementId',
      ].every(value.containsKey)) {
    throw const InvalidCategoryHistory();
  }
  return Category.restore(
    id: id,
    workspace: workspace,
    name: value['name'] as String,
    kind: CategoryKind.values.byName(value['kind'] as String),
    version: value['version'] as int,
    archived: value['archived'] as bool,
    parentId: value['parentId'] == null
        ? null
        : PublicId.parse(value['parentId'] as String),
    replacementId: value['replacementId'] == null
        ? null
        : PublicId.parse(value['replacementId'] as String),
  );
}

final class CategoriesAdapter {
  CategoriesAdapter(this.db);
  final ProbeDatabase db;
  void _enabled() {
    if (!db.categoryAware) throw StateError('Categories require schema 4.');
  }

  Future<CategoryCatalog> read(WorkspaceId workspace) async {
    _enabled();
    final rows = await db
        .customSelect(
          'SELECT id,payload FROM categories WHERE workspace=?',
          variables: [Variable.withString(workspace.toString())],
        )
        .get();
    return CategoryCatalog.restore(workspace, [
      for (final row in rows)
        categoryFromJson(
          workspace,
          PublicId.parse(row.read<String>('id')),
          row.read<String>('payload'),
        ),
    ]);
  }

  Future<CommitResult> mutate(
    OperationKey operation,
    CategoryMutation mutation, {
    void Function(String)? checkpoint,
  }) {
    _enabled();
    return OperationWriter(db).commit(
      operation,
      jsonEncode(mutation.input),
      mutation.id,
      () async {
        final before = await read(operation.workspace);
        final after = mutation.apply(before).get(mutation.id);
        final payload = jsonEncode(categoryJson(after));
        final ws = operation.workspace.toString();
        final ordinal =
            (await db
                    .customSelect(
                      'SELECT COALESCE(MAX(ordinal),0) AS n FROM category_changes WHERE workspace=?',
                      variables: [Variable.withString(ws)],
                    )
                    .getSingle())
                .read<int>('n');
        if (ordinal == 9223372036854775807)
          throw const InvalidCategoryHistory();
        await db.customStatement(
          'INSERT INTO categories VALUES(?,?,?) ON CONFLICT(workspace,id) DO UPDATE SET payload=excluded.payload',
          [ws, after.id.value, payload],
        );
        checkpoint?.call('category');
        await db.customStatement(
          'INSERT INTO category_changes VALUES(?,?,?,?,?)',
          [
            ws,
            ordinal + 1,
            operation.operation.toString(),
            after.id.value,
            payload,
          ],
        );
        checkpoint?.call('category-history');
      },
      mutation.auditKind,
      checkpoint,
    );
  }
}

/// Replay the ordered metadata history through the same Domain used for writes.
/// A source state cannot be accepted merely because its final tree looks valid.
Future<Set<(String, String)>> validateCategoryHistory(ProbeDatabase db) async {
  if (!db.categoryAware) throw const InvalidCategoryHistory();
  final states = <String, CategoryCatalog>{};
  final ordinals = <String, int>{};
  final verified = <(String, String)>{};
  final changes = await db.customSelect(
    '''SELECT h.*,r.input,r.result_id,a.kind AS audit_kind
    FROM category_changes h
    LEFT JOIN receipts r ON r.workspace=h.workspace AND r.operation_id=h.operation_id
    LEFT JOIN audit a ON a.workspace=h.workspace AND a.operation_id=h.operation_id
    ORDER BY h.workspace,h.ordinal''',
  ).get();
  for (final row in changes) {
    final ws = row.read<String>('workspace');
    final op = row.read<String>('operation_id');
    final id = row.read<String>('id');
    final ordinal = row.read<int>('ordinal');
    if (ordinal != (ordinals[ws] ?? 0) + 1 || !verified.add((ws, op))) {
      throw const InvalidCategoryHistory();
    }
    final mutation = CategoryMutation.fromInput(
      jsonDecode(row.read<String>('input')),
    );
    if (mutation.id.value != id ||
        row.read<String>('result_id') != id ||
        row.read<String>('audit_kind') != mutation.auditKind) {
      throw const InvalidCategoryHistory();
    }
    final state = mutation.apply(
      states[ws] ?? CategoryCatalog.empty(WorkspaceId.parse(ws)),
    );
    if (jsonEncode(categoryJson(state.get(mutation.id))) !=
        row.read<String>('payload')) {
      throw const InvalidCategoryHistory();
    }
    states[ws] = state;
    ordinals[ws] = ordinal;
  }
  final current = await db.customSelect('SELECT * FROM categories').get();
  if (current.length !=
      states.values.fold<int>(
        0,
        (sum, state) => sum + state.categories.length,
      )) {
    throw const InvalidCategoryHistory();
  }
  for (final row in current) {
    final ws = row.read<String>('workspace');
    final id = PublicId.parse(row.read<String>('id'));
    final state = states[ws];
    if (state == null ||
        jsonEncode(categoryJson(state.get(id))) !=
            row.read<String>('payload')) {
      throw const InvalidCategoryHistory();
    }
  }
  return verified;
}
