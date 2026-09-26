import 'dart:convert';
import 'dart:io';

import 'package:backup_envelope_probe/envelope.dart';
import 'package:drift/drift.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:modular_persistence_probe/adapters.dart';
import 'package:modular_persistence_probe/database.dart';

const _columns = {
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

/// Fixed prototype manifest. Every persisted table is included even if hidden.
final class SnapshotCodec {
  Future<List<int>> capture(
    ProbeDatabase source,
  ) => source.transaction(() async {
    // A new module or column must extend this manifest before backup is allowed.
    final persisted = await source
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type='table' AND name NOT GLOB 'sqlite_*'",
        )
        .get();
    if (persisted.length != _columns.length ||
        persisted.any((r) => !_columns.containsKey(r.read<String>('name'))))
      throw const InvalidSnapshot();
    for (final entry in _columns.entries) {
      final columns = await source
          .customSelect('PRAGMA table_info(${entry.key})')
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
    final bytes = utf8.encode(
      jsonEncode({
        'format': 'ledger-logical-probe',
        'version': 1,
        'schema': 2,
        'modules': _modules,
        'tables': tables,
      }),
    );
    if (bytes.length > EnvelopeCodec.maxPayloadBytes)
      throw const InvalidSnapshot();
    return bytes;
  });

  /// Imports only known columns with bound values into a brand-new staged file.
  Future<void> stage(
    List<int> bytes,
    File target, {
    ProbeDatabase Function(File)? openDatabase,
  }) async {
    final tables = _parse(bytes);
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
          root['version'] != 1 ||
          root['schema'] != 2)
        throw const InvalidSnapshot();
      final modules = root['modules'];
      if (modules is! Map ||
          modules.length != _modules.length ||
          !_modules.entries.every((e) => modules[e.key] == e.value))
        throw const InvalidSnapshot();
      final tables = root['tables'];
      if (tables is! Map || tables.length != _columns.length)
        throw const InvalidSnapshot();
      final result = <String, List<Map<String, dynamic>>>{};
      var count = 0;
      for (final entry in _columns.entries) {
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
          result[entry.key]!.add(row);
        }
      }
      return result;
    } on FormatException {
      throw const InvalidSnapshot();
    }
  }

  /// Known current prototype semantics, not a general future-module validator.
  Future<void> validate(ProbeDatabase db) async {
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
    for (final row in accountRows) {
      final account = await accounts.read(
        WorkspaceId.parse(row.read<String>('workspace')),
        PublicId.parse(row.read<String>('id')),
      );
      final payload = jsonDecode(row.read<String>('payload')) as Map;
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
    for (final event in events) {
      final ws = event.read<String>('workspace');
      final id = event.read<String>('id');
      final currency = Currency(
        event.read<String>('currency'),
        event.read<int>('scale'),
      );
      final date = BusinessDate.parse(event.read<String>('business_date'));
      final list = legs
          .where(
            (l) =>
                l.read<String>('workspace') == ws &&
                l.read<String>('event_id') == id,
          )
          .toList();
      if (list.isEmpty) throw const InvalidSnapshot();
      for (var index = 0; index < list.length; index++) {
        final leg = list[index];
        final account = await accounts.read(
          WorkspaceId.parse(ws),
          PublicId.parse(leg.read<String>('account_id')),
        );
        if (leg.read<int>('ordinal') != index ||
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
      UNION ALL SELECT e.id FROM events e WHERE (SELECT COUNT(*) FROM receipts r WHERE r.workspace=e.workspace AND r.result_id=e.id)!=1''',
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
          !['create-v1', 'posting-v1', 'archive-v1'].contains(input.first))
        throw const InvalidSnapshot();
      final ws = row.read<String>('workspace');
      final resultId = row.read<String>('result_id');
      final auditKind = row.read<String>('audit_kind');
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
      final event = events
          .where(
            (e) =>
                e.read<String>('workspace') == ws &&
                e.read<String>('id') == resultId,
          )
          .single;
      final isCreate = input.first == 'create-v1';
      if (isCreate &&
          (input.length != 4 ||
              input[2] is! Map ||
              event.read<String>('kind') != 'opening'))
        throw const InvalidSnapshot();
      final posting = isCreate ? input[3] : input;
      final eventLegs = legs
          .where(
            (l) =>
                l.read<String>('workspace') == ws &&
                l.read<String>('event_id') == resultId,
          )
          .toList();
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
