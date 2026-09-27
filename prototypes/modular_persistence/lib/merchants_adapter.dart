import 'dart:convert';

import 'package:merchants/merchants.dart';
import 'package:drift/drift.dart';
import 'package:foundation_values/foundation_values.dart';

import 'database.dart';
import 'operations.dart';

final class InvalidMerchantHistory implements Exception {
  const InvalidMerchantHistory();
  @override
  String toString() => 'InvalidMerchantHistory';
}

/// Versioned metadata command. Generated timestamps and result state are not
/// part of the retry key; public IDs and both merge revisions are retained.
final class MerchantMutation {
  MerchantMutation._(this.input);
  factory MerchantMutation.fromInput(Object? value) {
    if (value is! List) throw const InvalidMerchantHistory();
    final valid = switch (value) {
      ['merchant-v1', 'create', String _, String _] => true,
      ['merchant-v1', 'rename', String _, int _, String _] => true,
      ['merchant-v1', 'alias-add', String _, int _, String _] => true,
      ['merchant-v1', 'alias-remove', String _, int _, String _] => true,
      ['merchant-v1', 'archive', String _, int _, bool _] => true,
      ['merchant-v1', 'merge', String _, int _, String _, int _] => true,
      _ => false,
    };
    if (!valid) throw const InvalidMerchantHistory();
    // Own an immutable copy, not the caller's mutable list.
    return MerchantMutation._(List<Object?>.unmodifiable(value));
  }
  factory MerchantMutation.create(PublicId id, String name) =>
      MerchantMutation.fromInput([
        'merchant-v1',
        'create',
        id.value,
        name.trim(),
      ]);
  factory MerchantMutation.rename(PublicId id, int version, String name) =>
      MerchantMutation.fromInput([
        'merchant-v1',
        'rename',
        id.value,
        version,
        name.trim(),
      ]);
  factory MerchantMutation.archive(PublicId id, int version, bool archived) =>
      MerchantMutation.fromInput([
        'merchant-v1',
        'archive',
        id.value,
        version,
        archived,
      ]);
  factory MerchantMutation.merge(
    PublicId id,
    int version,
    PublicId target,
    int targetVersion,
  ) => MerchantMutation.fromInput([
    'merchant-v1',
    'merge',
    id.value,
    version,
    target.value,
    targetVersion,
  ]);

  factory MerchantMutation.alias(
    PublicId id,
    int version,
    String alias, {
    required bool remove,
  }) => MerchantMutation.fromInput([
    'merchant-v1',
    remove ? 'alias-remove' : 'alias-add',
    id.value,
    version,
    alias.trim(),
  ]);

  final List<Object?> input;
  PublicId get id => PublicId.parse(input[2] as String);
  String get auditKind => 'merchant.${input[1]}';
  MerchantCatalog apply(MerchantCatalog catalog) {
    final ws = catalog.workspace;
    return switch (input) {
      ['merchant-v1', 'create', String _, String name] => catalog.create(
        workspace: ws,
        id: id,
        name: name,
      ),
      ['merchant-v1', 'rename', String _, int version, String name] =>
        catalog.rename(
          workspace: ws,
          id: id,
          expectedVersion: version,
          name: name,
        ),
      ['merchant-v1', 'alias-add', String _, int version, String alias] =>
        catalog.addAlias(
          workspace: ws,
          id: id,
          expectedVersion: version,
          alias: alias,
        ),
      ['merchant-v1', 'alias-remove', String _, int version, String alias] =>
        catalog.removeAlias(
          workspace: ws,
          id: id,
          expectedVersion: version,
          alias: alias,
        ),
      ['merchant-v1', 'archive', String _, int version, bool archived] =>
        catalog.setArchived(
          workspace: ws,
          id: id,
          expectedVersion: version,
          archived: archived,
        ),
      [
        'merchant-v1',
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
      _ => throw const InvalidMerchantHistory(),
    };
  }
}

Map<String, Object?> merchantJson(Merchant merchant) => {
  'name': merchant.name,
  'aliases': merchant.aliases,
  'version': merchant.version,
  'archived': merchant.archived,
  'replacementId': merchant.replacementId?.value,
};

Merchant merchantFromJson(WorkspaceId workspace, PublicId id, String payload) {
  final value = jsonDecode(payload);
  if (value is! Map ||
      value.length != 5 ||
      ![
        'name',
        'aliases',
        'version',
        'archived',
        'replacementId',
      ].every(value.containsKey)) {
    throw const InvalidMerchantHistory();
  }
  return Merchant.restore(
    id: id,
    workspace: workspace,
    name: value['name'] as String,
    aliases: (value['aliases'] as List).cast<String>(),
    version: value['version'] as int,
    archived: value['archived'] as bool,
    replacementId: value['replacementId'] == null
        ? null
        : PublicId.parse(value['replacementId'] as String),
  );
}

final class MerchantsAdapter {
  MerchantsAdapter(this.db);
  final ProbeDatabase db;
  void _enabled() {
    if (!db.merchantsAware) throw StateError('Merchants require schema 7.');
  }

  Future<MerchantCatalog> read(WorkspaceId workspace) async {
    _enabled();
    final rows = await db
        .customSelect(
          'SELECT id,payload FROM merchants WHERE workspace=?',
          variables: [Variable.withString(workspace.toString())],
        )
        .get();
    return MerchantCatalog.restore(workspace, [
      for (final row in rows)
        merchantFromJson(
          workspace,
          PublicId.parse(row.read<String>('id')),
          row.read<String>('payload'),
        ),
    ]);
  }

  Future<CommitResult> mutate(
    OperationKey operation,
    MerchantMutation mutation, {
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
        final payload = jsonEncode(merchantJson(after));
        final ws = operation.workspace.toString();
        final ordinal = await currentSequence(operation.workspace);
        if (ordinal == 9223372036854775807)
          throw const InvalidMerchantHistory();
        await db.customStatement(
          'INSERT INTO merchants VALUES(?,?,?) ON CONFLICT(workspace,id) DO UPDATE SET payload=excluded.payload',
          [ws, after.id.value, payload],
        );
        checkpoint?.call('merchant');
        await db.customStatement(
          'INSERT INTO merchant_changes VALUES(?,?,?,?,?)',
          [
            ws,
            ordinal + 1,
            operation.operation.toString(),
            after.id.value,
            payload,
          ],
        );
        checkpoint?.call('merchant-history');
      },
      mutation.auditKind,
      checkpoint,
    );
  }

  Future<int> currentSequence(WorkspaceId workspace) async {
    _enabled();
    return (await db
            .customSelect(
              'SELECT COALESCE(MAX(ordinal),0) AS n FROM merchant_changes WHERE workspace=?',
              variables: [Variable.withString(workspace.toString())],
            )
            .getSingle())
        .read<int>('n');
  }
}

/// Replay the ordered metadata history through the same Domain used for writes.
/// A source state cannot be accepted merely because its final tree looks valid.
Future<Set<(String, String)>> validateMerchantHistory(
  ProbeDatabase db, {
  void Function(String workspace, int sequence, MerchantCatalog state)? visit,
}) async {
  if (!db.merchantsAware) throw const InvalidMerchantHistory();
  final states = <String, MerchantCatalog>{};
  final ordinals = <String, int>{};
  final verified = <(String, String)>{};
  final changes = await db.customSelect(
    '''SELECT h.*,r.input,r.result_id,a.kind AS audit_kind
    FROM merchant_changes h
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
      throw const InvalidMerchantHistory();
    }
    final mutation = MerchantMutation.fromInput(
      jsonDecode(row.read<String>('input')),
    );
    if (mutation.id.value != id ||
        row.read<String>('result_id') != id ||
        row.read<String>('audit_kind') != mutation.auditKind) {
      throw const InvalidMerchantHistory();
    }
    final state = mutation.apply(
      states[ws] ?? MerchantCatalog.empty(WorkspaceId.parse(ws)),
    );
    if (jsonEncode(merchantJson(state.get(mutation.id))) !=
        row.read<String>('payload')) {
      throw const InvalidMerchantHistory();
    }
    states[ws] = state;
    ordinals[ws] = ordinal;
    visit?.call(ws, ordinal, state);
  }
  final current = await db.customSelect('SELECT * FROM merchants').get();
  if (current.length !=
      states.values.fold<int>(
        0,
        (sum, state) => sum + state.merchants.length,
      )) {
    throw const InvalidMerchantHistory();
  }
  final seen = <(String, PublicId)>{};
  for (final row in current) {
    final ws = row.read<String>('workspace');
    final id = PublicId.parse(row.read<String>('id'));
    final state = states[ws];
    if (!seen.add((ws, id)) ||
        state == null ||
        jsonEncode(merchantJson(state.get(id))) !=
            row.read<String>('payload')) {
      throw const InvalidMerchantHistory();
    }
  }
  return verified;
}
