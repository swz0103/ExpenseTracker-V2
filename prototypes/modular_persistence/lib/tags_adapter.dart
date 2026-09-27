import 'dart:convert';

import 'package:tags/tags.dart';
import 'package:drift/drift.dart';
import 'package:foundation_values/foundation_values.dart';

import 'database.dart';
import 'operations.dart';

final class InvalidTagHistory implements Exception {
  const InvalidTagHistory();
  @override
  String toString() => 'InvalidTagHistory';
}

/// Versioned metadata command. Generated timestamps and result state are not
/// part of the retry key; public IDs and both merge revisions are retained.
final class TagMutation {
  TagMutation._(this.input);
  factory TagMutation.fromInput(Object? value) {
    if (value is! List) throw const InvalidTagHistory();
    final valid = switch (value) {
      ['tag-v1', 'create', String _, String _] => true,
      ['tag-v1', 'rename', String _, int _, String _] => true,
      ['tag-v1', 'archive', String _, int _, bool _] => true,
      ['tag-v1', 'merge', String _, int _, String _, int _] => true,
      _ => false,
    };
    if (!valid) throw const InvalidTagHistory();
    // Own an immutable copy, not the caller's mutable list.
    return TagMutation._(List<Object?>.unmodifiable(value));
  }
  factory TagMutation.create(PublicId id, String name) =>
      TagMutation.fromInput(['tag-v1', 'create', id.value, name.trim()]);
  factory TagMutation.rename(PublicId id, int version, String name) =>
      TagMutation.fromInput([
        'tag-v1',
        'rename',
        id.value,
        version,
        name.trim(),
      ]);
  factory TagMutation.archive(PublicId id, int version, bool archived) =>
      TagMutation.fromInput(['tag-v1', 'archive', id.value, version, archived]);
  factory TagMutation.merge(
    PublicId id,
    int version,
    PublicId target,
    int targetVersion,
  ) => TagMutation.fromInput([
    'tag-v1',
    'merge',
    id.value,
    version,
    target.value,
    targetVersion,
  ]);

  final List<Object?> input;
  PublicId get id => PublicId.parse(input[2] as String);
  String get auditKind => 'tag.${input[1]}';
  TagCatalog apply(TagCatalog catalog) {
    final ws = catalog.workspace;
    return switch (input) {
      ['tag-v1', 'create', String _, String name] => catalog.create(
        workspace: ws,
        id: id,
        name: name,
      ),
      ['tag-v1', 'rename', String _, int version, String name] =>
        catalog.rename(
          workspace: ws,
          id: id,
          expectedVersion: version,
          name: name,
        ),
      ['tag-v1', 'archive', String _, int version, bool archived] =>
        catalog.setArchived(
          workspace: ws,
          id: id,
          expectedVersion: version,
          archived: archived,
        ),
      [
        'tag-v1',
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
      _ => throw const InvalidTagHistory(),
    };
  }
}

Map<String, Object?> tagJson(Tag tag) => {
  'name': tag.name,
  'version': tag.version,
  'archived': tag.archived,
  'replacementId': tag.replacementId?.value,
};

Tag tagFromJson(WorkspaceId workspace, PublicId id, String payload) {
  final value = jsonDecode(payload);
  if (value is! Map ||
      value.length != 4 ||
      ![
        'name',
        'version',
        'archived',
        'replacementId',
      ].every(value.containsKey)) {
    throw const InvalidTagHistory();
  }
  return Tag.restore(
    id: id,
    workspace: workspace,
    name: value['name'] as String,
    version: value['version'] as int,
    archived: value['archived'] as bool,
    replacementId: value['replacementId'] == null
        ? null
        : PublicId.parse(value['replacementId'] as String),
  );
}

final class TagsAdapter {
  TagsAdapter(this.db);
  final ProbeDatabase db;
  void _enabled() {
    if (!db.tagsAware) throw StateError('Tags require schema 6.');
  }

  Future<TagCatalog> read(WorkspaceId workspace) async {
    _enabled();
    final rows = await db
        .customSelect(
          'SELECT id,payload FROM tags WHERE workspace=?',
          variables: [Variable.withString(workspace.toString())],
        )
        .get();
    return TagCatalog.restore(workspace, [
      for (final row in rows)
        tagFromJson(
          workspace,
          PublicId.parse(row.read<String>('id')),
          row.read<String>('payload'),
        ),
    ]);
  }

  Future<CommitResult> mutate(
    OperationKey operation,
    TagMutation mutation, {
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
        final payload = jsonEncode(tagJson(after));
        final ws = operation.workspace.toString();
        final ordinal = await currentSequence(operation.workspace);
        if (ordinal == 9223372036854775807) throw const InvalidTagHistory();
        await db.customStatement(
          'INSERT INTO tags VALUES(?,?,?) ON CONFLICT(workspace,id) DO UPDATE SET payload=excluded.payload',
          [ws, after.id.value, payload],
        );
        checkpoint?.call('tag');
        await db.customStatement('INSERT INTO tag_changes VALUES(?,?,?,?,?)', [
          ws,
          ordinal + 1,
          operation.operation.toString(),
          after.id.value,
          payload,
        ]);
        checkpoint?.call('tag-history');
      },
      mutation.auditKind,
      checkpoint,
    );
  }

  Future<int> currentSequence(WorkspaceId workspace) async {
    _enabled();
    return (await db
            .customSelect(
              'SELECT COALESCE(MAX(ordinal),0) AS n FROM tag_changes WHERE workspace=?',
              variables: [Variable.withString(workspace.toString())],
            )
            .getSingle())
        .read<int>('n');
  }
}

/// Replay the ordered metadata history through the same Domain used for writes.
/// A source state cannot be accepted merely because its final tree looks valid.
Future<Set<(String, String)>> validateTagHistory(
  ProbeDatabase db, {
  void Function(String workspace, int sequence, TagCatalog state)? visit,
}) async {
  if (!db.tagsAware) throw const InvalidTagHistory();
  final states = <String, TagCatalog>{};
  final ordinals = <String, int>{};
  final verified = <(String, String)>{};
  final changes = await db.customSelect(
    '''SELECT h.*,r.input,r.result_id,a.kind AS audit_kind
    FROM tag_changes h
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
      throw const InvalidTagHistory();
    }
    final mutation = TagMutation.fromInput(
      jsonDecode(row.read<String>('input')),
    );
    if (mutation.id.value != id ||
        row.read<String>('result_id') != id ||
        row.read<String>('audit_kind') != mutation.auditKind) {
      throw const InvalidTagHistory();
    }
    final state = mutation.apply(
      states[ws] ?? TagCatalog.empty(WorkspaceId.parse(ws)),
    );
    if (jsonEncode(tagJson(state.get(mutation.id))) !=
        row.read<String>('payload')) {
      throw const InvalidTagHistory();
    }
    states[ws] = state;
    ordinals[ws] = ordinal;
    visit?.call(ws, ordinal, state);
  }
  final current = await db.customSelect('SELECT * FROM tags').get();
  if (current.length !=
      states.values.fold<int>(0, (sum, state) => sum + state.tags.length)) {
    throw const InvalidTagHistory();
  }
  final seen = <(String, PublicId)>{};
  for (final row in current) {
    final ws = row.read<String>('workspace');
    final id = PublicId.parse(row.read<String>('id'));
    final state = states[ws];
    if (!seen.add((ws, id)) ||
        state == null ||
        jsonEncode(tagJson(state.get(id))) != row.read<String>('payload')) {
      throw const InvalidTagHistory();
    }
  }
  return verified;
}
