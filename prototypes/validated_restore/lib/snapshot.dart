import 'dart:convert';
import 'dart:io';

import 'package:backup_envelope_probe/envelope.dart';
import 'package:drift/drift.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:modular_persistence_probe/adapters.dart';
import 'package:modular_persistence_probe/database.dart';
import 'package:modular_persistence_probe/category_schema.dart';
import 'package:modular_persistence_probe/categories_adapter.dart';

const _financialColumns = {
  'accounts': ['workspace', 'id', 'payload'],
  'events': [
    'workspace',
    'id',
    'kind',
    'business_date',
    'income',
    'expense',
    'currency',
    'scale',
    'source_context',
  ],
  'legs': [
    'workspace',
    'event_id',
    'ordinal',
    'account_id',
    'amount',
    'currency',
    'scale',
    'role',
  ],
  'openings': ['workspace', 'account_id', 'event_id'],
  'allocations': ['workspace', 'event_id', 'category_id', 'amount'],
  'receipts': ['workspace', 'operation_id', 'input', 'result_id'],
  'audit': ['workspace', 'operation_id', 'entity_id', 'kind', 'recorded_at'],
};
const _integers = {'income', 'expense', 'scale', 'ordinal', 'amount'};
const _modules = {'accounts': 1, 'ledger': 2, 'operations': 1};

final class InvalidSnapshot implements Exception {
  const InvalidSnapshot();
  @override
  String toString() => 'InvalidSnapshot';
}

/// Fixed prototype manifest. All financial tables are portable; explicitly
/// versioned local identity is validated but regenerated at the destination.
final class SnapshotCodec {
  SnapshotCodec({bool generationAware = false, this.categoryAware = false})
    : generationAware = generationAware || categoryAware;
  final bool generationAware;
  final bool categoryAware;
  Map<String, List<String>> get _columns => {
    ..._financialColumns,
    if (categoryAware) ...categoryColumns,
  };

  /// Empty authority tables, validated by the same staged import path.
  List<int> empty() =>
      _encode({for (final name in _columns.keys) name: <Object>[]});
  int get _formatVersion => categoryAware ? 3 : (generationAware ? 2 : 1);
  int get _schemaVersion => categoryAware ? 4 : (generationAware ? 3 : 2);
  Map<String, int> get _manifest => {
    ..._modules,
    if (generationAware) 'local_identity': 1,
    if (categoryAware) 'categories': 1,
  };

  /// Upgrades the portable manifest only; target local identity is always regenerated.
  List<int> canonicalize(List<int> bytes) => _encode(_parse(bytes));

  List<int> _encode(Object tables) {
    final bytes = utf8.encode(
      jsonEncode({
        'format': 'ledger-logical-probe',
        'version': _formatVersion,
        'schema': _schemaVersion,
        'modules': _manifest,
        'tables': tables,
      }),
    );
    if (bytes.length > EnvelopeCodec.maxPayloadBytes)
      throw const InvalidSnapshot();
    return bytes;
  }

  Future<List<int>> capture(
    ProbeDatabase source,
  ) => source.transaction(() async {
    // A new module or column must extend this manifest before backup is allowed.
    final persisted = await source
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type='table' AND name NOT GLOB 'sqlite_*'",
        )
        .get();
    final localTables = {
      ..._columns,
      if (generationAware)
        'storage_identity': [
          'singleton',
          'generation',
          'slot',
          'operation',
          'fingerprint',
        ],
    };
    if (persisted.length != localTables.length ||
        persisted.any((r) => !localTables.containsKey(r.read<String>('name'))))
      throw const InvalidSnapshot();
    for (final entry in localTables.entries) {
      final columns = await source
          .customSelect('PRAGMA table_xinfo(${entry.key})')
          .get();
      if (columns.length != entry.value.length ||
          columns.any((r) => !entry.value.contains(r.read<String>('name'))))
        throw const InvalidSnapshot();
    }
    await validate(source);
    final tables = <String, Object>{};
    var count = 0;
    for (final entry in _columns.entries) {
      final rows = await source
          .customSelect(
            'SELECT ${entry.value.join(',')} FROM ${entry.key} ORDER BY rowid',
          )
          .get();
      count += rows.length;
      if (count > 50000) throw const InvalidSnapshot();
      tables[entry.key] = [
        for (final row in rows)
          {
            for (final column in entry.value)
              column: row.data[column] is int
                  ? row.data[column].toString()
                  : row.data[column],
          },
      ];
    }
    return _encode(tables);
  });

  /// Imports only known columns with bound values into a brand-new staged file.
  Future<void> stage(
    List<int> bytes,
    File target, {
    ProbeDatabase Function(File)? openDatabase,
    void Function(String)? checkpoint,
  }) async {
    final tables = _parse(bytes);
    if (generationAware && openDatabase == null) throw const InvalidSnapshot();
    if (await target.exists()) throw StateError('Stage file already exists.');
    final db = openDatabase == null
        ? ProbeDatabase(target)
        : openDatabase(target);
    try {
      await db.transaction(() async {
        for (final entry in _columns.entries) {
          for (final row in tables[entry.key]!) {
            await db.customStatement(
              'INSERT INTO ${entry.key} (${entry.value.join(',')}) VALUES (${List.filled(entry.value.length, '?').join(',')})',
              [
                for (final column in entry.value)
                  _integers.contains(column)
                      ? _integer(row[column])
                      : row[column],
              ],
            );
          }
          checkpoint?.call('table:${entry.key}');
        }
        await validate(db);
      });
    } finally {
      await db.close();
    }
  }

  Map<String, List<Map<String, dynamic>>> _parse(List<int> bytes) {
    if (bytes.length > EnvelopeCodec.maxPayloadBytes)
      throw const InvalidSnapshot();
    try {
      final root = jsonDecode(utf8.decode(bytes));
      if (root is! Map<String, dynamic> ||
          root.length != 5 ||
          root['format'] != 'ledger-logical-probe' ||
          !((root['version'] == 1 && root['schema'] == 2) ||
              (generationAware &&
                  root['version'] == 2 &&
                  root['schema'] == 3) ||
              (categoryAware && root['version'] == 3 && root['schema'] == 4)))
        throw const InvalidSnapshot();
      final modules = root['modules'];
      final expectedModules = {
        ..._modules,
        if (root['version'] != 1) 'local_identity': 1,
        if (root['version'] == 3) 'categories': 1,
      };
      if (modules is! Map ||
          modules.length != expectedModules.length ||
          !expectedModules.entries.every((e) => modules[e.key] == e.value))
        throw const InvalidSnapshot();
      final tables = root['tables'];
      final inputColumns = root['version'] == 3 ? _columns : _financialColumns;
      if (tables is! Map || tables.length != inputColumns.length)
        throw const InvalidSnapshot();
      final result = <String, List<Map<String, dynamic>>>{
        for (final name in _columns.keys) name: [],
      };
      var count = 0;
      for (final entry in inputColumns.entries) {
        final rows = tables[entry.key];
        if (rows is! List) throw const InvalidSnapshot();
        count += rows.length;
        if (count > 50000) throw const InvalidSnapshot();
        result[entry.key] = [];
        for (final row in rows) {
          if (row is! Map<String, dynamic> ||
              row.length != entry.value.length ||
              !entry.value.every(row.containsKey))
            throw const InvalidSnapshot();
          for (final column in entry.value) {
            if (row[column] is! String) throw const InvalidSnapshot();
            if (_integers.contains(column)) _integer(row[column]);
            if (column == 'workspace' ||
                column == 'id' ||
                column.endsWith('_id'))
              PublicId.parse(row[column] as String);
          }
          result[entry.key]!.add({
            for (final column in entry.value) column: row[column],
          });
        }
      }
      return result;
    } on FormatException {
      throw const InvalidSnapshot();
    }
  }

  /// Known current prototype semantics, not a general future-module validator.
  Future<void> validate(ProbeDatabase db) async {
    if (generationAware != (db.storageBinding != null) ||
        categoryAware != db.categoryAware)
      throw const InvalidSnapshot();
    if (generationAware) await db.verifyStorageBinding();
    var categoryOperations = <(String, String)>{};
    if (categoryAware) {
      try {
        categoryOperations = await validateCategoryHistory(db);
      } catch (_) {
        throw const InvalidSnapshot();
      }
    }
    if ((await db.customSelect('PRAGMA foreign_key_check').get()).isNotEmpty ||
        (await db.customSelect('PRAGMA integrity_check').getSingle())
                .data
                .values
                .single !=
            'ok')
      throw const InvalidSnapshot();
    if ((await db
                .customSelect('SELECT COUNT(*) AS n FROM allocations')
                .getSingle())
            .read<int>('n') !=
        0) {
      // Current persistence cannot create Categories references; do not invent support.
      throw const InvalidSnapshot();
    }
    final accounts = AccountsAdapter(db);
    final ledger = LedgerAdapter(db);
    final accountRows = await db
        .customSelect('SELECT workspace,id,payload FROM accounts')
        .get();
    final accountFacts =
        <(String, String), ({Currency currency, BusinessDate openedOn})>{};
    for (final row in accountRows) {
      final account = await accounts.read(
        WorkspaceId.parse(row.read<String>('workspace')),
        PublicId.parse(row.read<String>('id')),
      );
      final payload = jsonDecode(row.read<String>('payload')) as Map;
      accountFacts[(account.workspace.toString(), account.id.value)] = (
        currency: account.currency,
        openedOn: account.openedOn,
      );
      if (payload.length != accountJson(account).length ||
          !accountJson(account).keys.every(payload.containsKey))
        throw const InvalidSnapshot();
      final opening = await db
          .customSelect(
            '''SELECT e.business_date FROM openings o
        JOIN events e ON e.workspace=o.workspace AND e.id=o.event_id
        WHERE o.workspace=? AND o.account_id=?''',
            variables: [
              Variable.withString(account.workspace.toString()),
              Variable.withString(account.id.value),
            ],
          )
          .get();
      if (opening.length != 1 ||
          opening.single.read<String>('business_date') !=
              account.openedOn.toString())
        throw const InvalidSnapshot();
      await ledger.balance(
        PostingAccount(
          id: account.id,
          workspace: account.workspace,
          currency: account.currency,
          expectedVersion: account.version,
        ),
      );
    }
    final legs = await db
        .customSelect('SELECT * FROM legs ORDER BY workspace,event_id,ordinal')
        .get();
    final events = await db.customSelect('SELECT * FROM events').get();
    final eventsById = <(String, String), QueryRow>{
      for (final event in events)
        (event.read<String>('workspace'), event.read<String>('id')): event,
    };
    if (eventsById.length != events.length) throw const InvalidSnapshot();
    final legsByEvent = <(String, String), List<QueryRow>>{};
    for (final leg in legs) {
      (legsByEvent[(
                leg.read<String>('workspace'),
                leg.read<String>('event_id'),
              )] ??=
              [])
          .add(leg);
    }
    for (final event in events) {
      final ws = event.read<String>('workspace');
      final id = event.read<String>('id');
      final currency = Currency(
        event.read<String>('currency'),
        event.read<int>('scale'),
      );
      final date = BusinessDate.parse(event.read<String>('business_date'));
      final list = legsByEvent[(ws, id)] ?? const <QueryRow>[];
      if (list.isEmpty) throw const InvalidSnapshot();
      for (var index = 0; index < list.length; index++) {
        final leg = list[index];
        final account = accountFacts[(ws, leg.read<String>('account_id'))];
        if (account == null ||
            leg.read<int>('ordinal') != index ||
            account.currency != currency ||
            Currency(leg.read<String>('currency'), leg.read<int>('scale')) !=
                currency ||
            date.compareTo(account.openedOn) < 0)
          throw const InvalidSnapshot();
      }
      final amounts = list
          .map((l) => BigInt.from(l.read<int>('amount')))
          .toList();
      final income = BigInt.from(event.read<int>('income'));
      final expense = BigInt.from(event.read<int>('expense'));
      final kind = event.read<String>('kind');
      if (kind == 'transfer') {
        if (list.length < 2 ||
            list.length > 3 ||
            amounts[0] >= BigInt.zero ||
            amounts[1] != -amounts[0] ||
            list[0].read<String>('role') != 'principal' ||
            list[1].read<String>('role') != 'principal' ||
            list[0].read<String>('account_id') ==
                list[1].read<String>('account_id') ||
            income != BigInt.zero ||
            (list.length == 2 && expense != BigInt.zero) ||
            (list.length == 3 &&
                (list[2].read<String>('role') != 'fee' ||
                    amounts[2] >= BigInt.zero ||
                    expense != -amounts[2] ||
                    list[2].read<String>('account_id') !=
                        list[0].read<String>('account_id'))))
          throw const InvalidSnapshot();
      } else {
        if (list.length != 1 || list.single.read<String>('role') != 'principal')
          throw const InvalidSnapshot();
        final amount = amounts.single;
        if (kind == 'opening') {
          if (income != BigInt.zero || expense != BigInt.zero)
            throw const InvalidSnapshot();
        } else if (kind == 'income') {
          if (amount <= BigInt.zero ||
              income != amount ||
              expense != BigInt.zero)
            throw const InvalidSnapshot();
        } else if (kind == 'expense') {
          if (amount >= BigInt.zero ||
              expense != -amount ||
              income != BigInt.zero)
            throw const InvalidSnapshot();
        } else {
          throw const InvalidSnapshot();
        }
      }
    }
    final invalidOpenings = await db.customSelect(
      '''SELECT e.id FROM events e WHERE e.kind='opening' AND NOT EXISTS
      (SELECT 1 FROM openings o JOIN legs l ON l.workspace=o.workspace AND l.event_id=o.event_id AND l.account_id=o.account_id
       WHERE o.workspace=e.workspace AND o.event_id=e.id)
      UNION ALL SELECT o.event_id FROM openings o JOIN events e ON e.workspace=o.workspace AND e.id=o.event_id WHERE e.kind!='opening' ''',
    ).get();
    if (invalidOpenings.isNotEmpty) throw const InvalidSnapshot();
    final orphanReceipts = await db.customSelect(
      '''SELECT r.operation_id FROM receipts r LEFT JOIN audit a
      ON a.workspace=r.workspace AND a.operation_id=r.operation_id WHERE a.operation_id IS NULL OR a.entity_id!=r.result_id
      UNION ALL SELECT e.id FROM events e LEFT JOIN
      (SELECT r.workspace,r.result_id,COUNT(*) AS n FROM receipts r
       JOIN audit a ON a.workspace=r.workspace AND a.operation_id=r.operation_id
       WHERE a.kind NOT LIKE 'category.%' GROUP BY r.workspace,r.result_id) counts
      ON counts.workspace=e.workspace AND counts.result_id=e.id WHERE COALESCE(counts.n,0)!=1''',
    ).get();
    if (orphanReceipts.isNotEmpty) throw const InvalidSnapshot();
    for (final row
        in await db
            .customSelect(
              'SELECT r.*,a.kind AS audit_kind FROM receipts r JOIN audit a ON a.workspace=r.workspace AND a.operation_id=r.operation_id',
            )
            .get()) {
      final input = jsonDecode(row.read<String>('input'));
      if (input is! List ||
          input.isEmpty ||
          ![
            'create-v1',
            'posting-v1',
            'archive-v1',
            if (categoryAware) 'category-v1',
          ].contains(input.first))
        throw const InvalidSnapshot();
      final ws = row.read<String>('workspace');
      final resultId = row.read<String>('result_id');
      final auditKind = row.read<String>('audit_kind');
      if (input.first == 'category-v1') {
        if (!categoryOperations.remove((
          ws,
          row.read<String>('operation_id'),
        ))) {
          throw const InvalidSnapshot();
        }
        continue;
      }
      if (input.first == 'archive-v1') {
        if (input.length != 3 ||
            input[1] != resultId ||
            input[2] is! int ||
            input[2] < 1 ||
            auditKind != 'account.archive')
          throw const InvalidSnapshot();
        final account = await accounts.read(
          WorkspaceId.parse(ws),
          PublicId.parse(resultId),
        );
        if (account.version <= input[2]) throw const InvalidSnapshot();
        continue;
      }
      final event = eventsById[(ws, resultId)];
      if (event == null) throw const InvalidSnapshot();
      final isCreate = input.first == 'create-v1';
      if (isCreate &&
          (input.length != 4 ||
              input[2] is! Map ||
              event.read<String>('kind') != 'opening'))
        throw const InvalidSnapshot();
      final posting = isCreate ? input[3] : input;
      final eventLegs = legsByEvent[(ws, resultId)] ?? const <QueryRow>[];
      if (posting is! List ||
          posting.length != 3 + eventLegs.length ||
          posting[0] != 'posting-v1' ||
          posting[1] != event.read<String>('kind') ||
          posting[2] != event.read<String>('business_date') ||
          auditKind != (isCreate ? 'account.open' : 'ledger.${posting[1]}'))
        throw const InvalidSnapshot();
      if (isCreate &&
          (input[1] != eventLegs.single.read<String>('account_id') ||
              input[2]['openedOn'] != posting[2] ||
              input[2]['version'] != 1 ||
              input[2]['state'] != 'active'))
        throw const InvalidSnapshot();
      for (var i = 0; i < eventLegs.length; i++) {
        final leg = eventLegs[i];
        final encoded = posting[i + 3];
        if (encoded is! List ||
            encoded.length != 4 ||
            encoded[0] != leg.read<String>('account_id') ||
            encoded[1] is! int ||
            encoded[1] < 1 ||
            encoded[3] != leg.read<String>('role') ||
            jsonEncode(encoded[2]) !=
                jsonEncode(
                  Money(
                    Currency(
                      leg.read<String>('currency'),
                      leg.read<int>('scale'),
                    ),
                    BigInt.from(leg.read<int>('amount')),
                  ).toJson(),
                ))
          throw const InvalidSnapshot();
      }
    }
    if (categoryOperations.isNotEmpty) throw const InvalidSnapshot();
    for (final row
        in await db.customSelect('SELECT recorded_at FROM audit').get()) {
      UtcInstant.parse(row.read<String>('recorded_at'));
    }
  }
}

int _integer(Object? value) {
  if (value is! String ||
      value.length > 20 ||
      !RegExp(r'^-?(0|[1-9][0-9]*)$').hasMatch(value))
    throw const InvalidSnapshot();
  final amount = BigInt.parse(value);
  if (amount < Money.minMinorUnits || amount > Money.maxMinorUnits)
    throw const InvalidSnapshot();
  return amount.toInt();
}
