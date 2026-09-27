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
import 'package:modular_persistence_probe/allocation_schema.dart';
import 'package:modular_persistence_probe/allocation_validation.dart';
import 'package:modular_persistence_probe/tag_schema.dart';
import 'package:modular_persistence_probe/merchant_schema.dart';
import 'package:modular_persistence_probe/merchant_reference_schema.dart';
import 'package:modular_persistence_probe/merchant_reference_validation.dart';
import 'package:modular_persistence_probe/tag_reference_schema.dart';
import 'package:modular_persistence_probe/tag_reference_validation.dart';

part 'refund_snapshot.dart';
part 'reversal_snapshot.dart';

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
const _integers = {
  'income',
  'expense',
  'scale',
  'ordinal',
  'amount',
  'category_version',
  'category_sequence',
  'tag_version',
  'tag_sequence',
  'merchant_version',
  'merchant_sequence',
};
const _modules = {'accounts': 1, 'ledger': 2, 'operations': 1};

final class InvalidSnapshot implements Exception {
  const InvalidSnapshot();
  @override
  String toString() => 'InvalidSnapshot';
}

/// Fixed prototype manifest. All financial tables are portable; explicitly
/// versioned local identity is validated but regenerated at the destination.
final class SnapshotCodec {
  static const maxRows = 50000;
  SnapshotCodec({
    bool generationAware = false,
    bool categoryAware = false,
    bool categoryReferences = false,
    bool tagsAware = false,
    bool merchantsAware = false,
    bool transfersAware = false,
    bool fxTransfersAware = false,
    bool refundsAware = false,
    this.reversalsAware = false,
  }) : refundsAware = refundsAware || reversalsAware,
       fxTransfersAware = fxTransfersAware || refundsAware || reversalsAware,
       transfersAware =
           transfersAware || fxTransfersAware || refundsAware || reversalsAware,
       merchantsAware =
           merchantsAware ||
           transfersAware ||
           fxTransfersAware ||
           refundsAware ||
           reversalsAware,
       tagsAware =
           tagsAware ||
           merchantsAware ||
           transfersAware ||
           fxTransfersAware ||
           refundsAware ||
           reversalsAware,
       categoryReferences =
           categoryReferences ||
           tagsAware ||
           merchantsAware ||
           transfersAware ||
           fxTransfersAware ||
           refundsAware ||
           reversalsAware,
       categoryAware =
           categoryAware ||
           categoryReferences ||
           tagsAware ||
           merchantsAware ||
           transfersAware ||
           fxTransfersAware ||
           refundsAware ||
           reversalsAware,
       generationAware =
           generationAware ||
           categoryAware ||
           categoryReferences ||
           tagsAware ||
           merchantsAware ||
           transfersAware ||
           fxTransfersAware ||
           refundsAware ||
           reversalsAware;
  final bool generationAware;
  final bool categoryAware;
  final bool categoryReferences;
  final bool tagsAware;
  final bool merchantsAware;
  final bool transfersAware;
  final bool fxTransfersAware;
  final bool refundsAware;
  final bool reversalsAware;
  Map<String, List<String>> get _columns => {
    ..._financialColumns,
    if (fxTransfersAware) 'event_fx': fxTransferColumns,
    if (refundsAware) 'event_refunds': refundColumns,
    if (reversalsAware) 'event_reversals': reversalColumns,
    if (categoryAware) ...categoryColumns,
    if (tagsAware) ...tagColumns,
    if (merchantsAware) ...merchantColumns,
    if (merchantsAware) 'event_merchants': merchantReferenceColumns,
    if (tagsAware) 'event_tags': tagReferenceColumns,
    if (categoryReferences) 'allocations': allocationReferenceColumns,
  };

  /// Empty authority tables, validated by the same staged import path.
  List<int> empty() =>
      _encode({for (final name in _columns.keys) name: <Object>[]});
  int get _formatVersion => reversalsAware
      ? 10
      : refundsAware
      ? 9
      : fxTransfersAware
      ? 8
      : transfersAware
      ? 7
      : merchantsAware
      ? 6
      : tagsAware
      ? 5
      : categoryReferences
      ? 4
      : (categoryAware ? 3 : (generationAware ? 2 : 1));
  int get _schemaVersion => reversalsAware
      ? 11
      : refundsAware
      ? 10
      : fxTransfersAware
      ? 9
      : transfersAware
      ? 8
      : merchantsAware
      ? 7
      : tagsAware
      ? 6
      : categoryReferences
      ? 5
      : (categoryAware ? 4 : (generationAware ? 3 : 2));
  Map<String, int> get _manifest => {
    ..._modules,
    if (categoryReferences) 'ledger': 3,
    if (generationAware) 'local_identity': 1,
    if (categoryAware) 'categories': 1,
    if (tagsAware) 'tags': 1,
    if (tagsAware) 'ledger_tags': 1,
    if (merchantsAware) 'merchants': 1,
    if (merchantsAware) 'ledger_merchants': 1,
    if (transfersAware) 'session_transfers': 1,
    if (fxTransfersAware) 'ledger_fx_transfers': 1,
    if (refundsAware) 'ledger_refunds': 1,
    if (reversalsAware) 'ledger_reversals': 1,
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
      if (count > maxRows) throw const InvalidSnapshot();
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
              (categoryAware && root['version'] == 3 && root['schema'] == 4) ||
              (categoryReferences &&
                  root['version'] == 4 &&
                  root['schema'] == 5) ||
              (tagsAware && root['version'] == 5 && root['schema'] == 6) ||
              (merchantsAware && root['version'] == 6 && root['schema'] == 7) ||
              (transfersAware && root['version'] == 7 && root['schema'] == 8) ||
              (fxTransfersAware &&
                  root['version'] == 8 &&
                  root['schema'] == 9) ||
              (refundsAware && root['version'] == 9 && root['schema'] == 10) ||
              (reversalsAware &&
                  root['version'] == 10 &&
                  root['schema'] == 11)))
        throw const InvalidSnapshot();
      final modules = root['modules'];
      final expectedModules = {
        ..._modules,
        if (root['version'] >= 4) 'ledger': 3,
        if (root['version'] != 1) 'local_identity': 1,
        if (root['version'] >= 3) 'categories': 1,
        if (root['version'] >= 5) 'tags': 1,
        if (root['version'] >= 5) 'ledger_tags': 1,
        if (root['version'] >= 6) 'merchants': 1,
        if (root['version'] >= 6) 'ledger_merchants': 1,
        if (root['version'] >= 7) 'session_transfers': 1,
        if (root['version'] >= 8) 'ledger_fx_transfers': 1,
        if (root['version'] >= 9) 'ledger_refunds': 1,
        if (root['version'] >= 10) 'ledger_reversals': 1,
      };
      if (modules is! Map ||
          modules.length != expectedModules.length ||
          !expectedModules.entries.every((e) => modules[e.key] == e.value))
        throw const InvalidSnapshot();
      final tables = root['tables'];
      final inputColumns = {
        ..._financialColumns,
        if (root['version'] >= 8) 'event_fx': fxTransferColumns,
        if (root['version'] >= 9) 'event_refunds': refundColumns,
        if (root['version'] >= 10) 'event_reversals': reversalColumns,
        if (root['version'] >= 3) ...categoryColumns,
        if (root['version'] >= 5) ...tagColumns,
        if (root['version'] >= 6) ...merchantColumns,
        if (root['version'] >= 6) 'event_merchants': merchantReferenceColumns,
        if (root['version'] >= 5) 'event_tags': tagReferenceColumns,
        if (root['version'] >= 4) 'allocations': allocationReferenceColumns,
      };
      if (tables is! Map || tables.length != inputColumns.length)
        throw const InvalidSnapshot();
      final result = <String, List<Map<String, dynamic>>>{
        for (final name in _columns.keys) name: [],
      };
      var count = 0;
      for (final entry in inputColumns.entries) {
        final rows = tables[entry.key];
        if (rows is! List) throw const InvalidSnapshot();
        // No released older writer could persist validated selections. Never
        // invent a revision/sequence while converting an old allocation row.
        if (entry.key == 'allocations' &&
            root['version'] < 4 &&
            rows.isNotEmpty) {
          throw const InvalidSnapshot();
        }
        count += rows.length;
        if (count > maxRows) throw const InvalidSnapshot();
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
        categoryAware != db.categoryAware ||
        categoryReferences != db.categoryReferences ||
        tagsAware != db.tagsAware ||
        merchantsAware != db.merchantsAware ||
        transfersAware != db.transfersAware ||
        fxTransfersAware != db.fxTransfersAware ||
        refundsAware != db.refundsAware ||
        reversalsAware != db.reversalsAware)
      throw const InvalidSnapshot();
    if (generationAware) await db.verifyStorageBinding();
    var categoryOperations = <(String, String)>{};
    if (categoryAware) {
      try {
        categoryOperations = categoryReferences
            ? await validateAllocationHistory(db)
            : await validateCategoryHistory(db);
      } catch (_) {
        throw const InvalidSnapshot();
      }
    }
    var tagOperations = <(String, String)>{};
    if (tagsAware) {
      try {
        tagOperations = await validateTagReferences(db);
      } catch (_) {
        throw const InvalidSnapshot();
      }
    }
    var merchantOperations = <(String, String)>{};
    if (merchantsAware) {
      try {
        merchantOperations = await validateMerchantReferences(db);
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
    final allocations = await db
        .customSelect('SELECT * FROM allocations')
        .get();
    if (!categoryReferences && allocations.isNotEmpty) {
      throw const InvalidSnapshot();
    }
    final allocationsByEvent = <(String, String), Map<String, QueryRow>>{};
    for (final row in allocations) {
      final eventAllocations =
          allocationsByEvent[(
                row.read<String>('workspace'),
                row.read<String>('event_id'),
              )] ??=
              {};
      final category = row.read<String>('category_id');
      if (eventAllocations.containsKey(category)) throw const InvalidSnapshot();
      eventAllocations[category] = row;
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
    final conversions = <(String, String), String>{};
    if (fxTransfersAware) {
      for (final row in await db.customSelect('SELECT * FROM event_fx').get()) {
        conversions[(
          row.read<String>('workspace'),
          row.read<String>('event_id'),
        )] = row.read<String>(
          'context',
        );
      }
    }
    var refundLinks = <(String, String), String>{};
    if (refundsAware) {
      try {
        refundLinks = await _validateRefundHistory(
          db,
          events,
          allocationsByEvent,
        );
      } catch (_) {
        throw const InvalidSnapshot();
      }
    }
    final reversalLinks = reversalsAware
        ? await _validateReversalHistory(db, events)
        : <(String, String), ({String original, String reason})>{};
    final checkedConversions = <(String, String)>{};
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
            account.currency !=
                Currency(
                  leg.read<String>('currency'),
                  leg.read<int>('scale'),
                ) ||
            (!((fxTransfersAware &&
                        (event.read<String>('kind') == 'transfer' ||
                            (reversalsAware &&
                                event.read<String>('kind') == 'reversal')) &&
                        index == 1) ||
                    (refundsAware && event.read<String>('kind') == 'refund')) &&
                account.currency != currency) ||
            date.compareTo(account.openedOn) < 0)
          throw const InvalidSnapshot();
      }
      final amounts = list
          .map((l) => BigInt.from(l.read<int>('amount')))
          .toList();
      final income = BigInt.from(event.read<int>('income'));
      final expense = BigInt.from(event.read<int>('expense'));
      final kind = event.read<String>('kind');
      final attributed = allocationsByEvent[(ws, id)]?.values;
      if (attributed != null && kind != 'reversal') {
        var total = BigInt.zero;
        for (final row in attributed) {
          final amount = BigInt.from(row.read<int>('amount'));
          if (amount <= BigInt.zero) throw const InvalidSnapshot();
          total += amount;
        }
        if ((kind != 'income' &&
                kind != 'expense' &&
                !(refundsAware && kind == 'refund')) ||
            total !=
                (kind == 'income'
                    ? income
                    : kind == 'refund'
                    ? -expense
                    : expense)) {
          throw const InvalidSnapshot();
        }
      }
      if (kind == 'reversal') {
        if (!reversalLinks.containsKey((ws, id))) throw const InvalidSnapshot();
        if (conversions.containsKey((ws, id))) checkedConversions.add((ws, id));
      } else if (kind == 'refund') {
        if (!refundsAware ||
            !refundLinks.containsKey((ws, id)) ||
            list.length != 1 ||
            list.single.read<String>('role') != 'principal' ||
            amounts.single <= BigInt.zero ||
            income != BigInt.zero ||
            expense >= BigInt.zero) {
          throw const InvalidSnapshot();
        }
        final received = Money(
          Currency(
            list.single.read<String>('currency'),
            list.single.read<int>('scale'),
          ),
          amounts.single,
        );
        if (received.currency != currency) {
          try {
            final conversion = ActualConversion(
              Money(currency, -expense),
              received,
            );
            if (conversions[(ws, id)] != jsonEncode(conversion.toJson())) {
              throw const InvalidSnapshot();
            }
          } catch (_) {
            throw const InvalidSnapshot();
          }
          checkedConversions.add((ws, id));
        } else if (amounts.single != -expense ||
            conversions.containsKey((ws, id))) {
          throw const InvalidSnapshot();
        }
      } else if (kind == 'transfer') {
        // Match admission: the full outgoing principal plus fee must fit Money.
        Money(currency, -amounts[0] + expense);
        final foreign =
            list.length >= 2 &&
            Currency(
                  list[1].read<String>('currency'),
                  list[1].read<int>('scale'),
                ) !=
                currency;
        if (foreign) {
          if (!fxTransfersAware) throw const InvalidSnapshot();
          try {
            final context = ActualConversion(
              Money(currency, -amounts[0]),
              Money(
                Currency(
                  list[1].read<String>('currency'),
                  list[1].read<int>('scale'),
                ),
                amounts[1],
              ),
            );
            if (conversions[(ws, id)] != jsonEncode(context.toJson()))
              throw const InvalidSnapshot();
          } catch (_) {
            throw const InvalidSnapshot();
          }
          checkedConversions.add((ws, id));
        } else if (conversions.containsKey((ws, id))) {
          throw const InvalidSnapshot();
        }
        if (list.length < 2 ||
            list.length > 3 ||
            amounts[0] >= BigInt.zero ||
            amounts[1] <= BigInt.zero ||
            (!foreign && amounts[1] != -amounts[0]) ||
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
        if (conversions.containsKey((ws, id))) throw const InvalidSnapshot();
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
    if (checkedConversions.length != conversions.length)
      throw const InvalidSnapshot();
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
       WHERE a.kind NOT LIKE 'category.%' AND a.kind NOT LIKE 'tag.%' AND a.kind NOT LIKE 'merchant.%' GROUP BY r.workspace,r.result_id) counts
      ON counts.workspace=e.workspace AND counts.result_id=e.id WHERE COALESCE(counts.n,0)!=1''',
    ).get();
    if (orphanReceipts.isNotEmpty) throw const InvalidSnapshot();
    for (final row
        in await db
            .customSelect(
              'SELECT r.*,a.kind AS audit_kind FROM receipts r JOIN audit a ON a.workspace=r.workspace AND a.operation_id=r.operation_id',
            )
            .get()) {
      var input = jsonDecode(row.read<String>('input'));
      if (input is! List ||
          input.isEmpty ||
          ![
            'create-v1',
            'posting-v1',
            if (fxTransfersAware) 'fx-posting-v1',
            if (refundsAware) 'refund-posting-v1',
            if (reversalsAware) 'reversal-posting-v1',
            if (categoryReferences) 'posting-v2',
            'archive-v1',
            if (categoryAware) 'category-v1',
            if (tagsAware) 'tag-v1',
            if (tagsAware) 'tagged-post-v1',
            if (merchantsAware) 'merchant-v1',
            if (merchantsAware) 'merchant-post-v1',
          ].contains(input.first))
        throw const InvalidSnapshot();
      final ws = row.read<String>('workspace');
      final resultId = row.read<String>('result_id');
      final auditKind = row.read<String>('audit_kind');
      if (input.first == 'merchant-v1') {
        if (!merchantOperations.remove((ws, row.read<String>('operation_id'))))
          throw const InvalidSnapshot();
        continue;
      }
      if (input.first == 'merchant-post-v1') input = input[1];
      if (input.first == 'tag-v1') {
        if (!tagOperations.remove((ws, row.read<String>('operation_id'))))
          throw const InvalidSnapshot();
        continue;
      }
      if (input.first == 'tagged-post-v1') {
        // The tag validator checks the wrapper and its exact retained rows.
        input = input[1];
      }
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
      final context = conversions[(ws, resultId)];
      if (input.first == 'reversal-posting-v1') {
        final link = reversalLinks[(ws, resultId)];
        if (!reversalsAware ||
            input.length != 5 ||
            link == null ||
            input[1] != link.original ||
            input[2] != link.reason ||
            event.read<String>('kind') != 'reversal' ||
            (context == null
                ? input[4] != null
                : jsonEncode(input[4]) != context) ||
            input[3] is! List ||
            (input[3] as List).isEmpty) {
          throw const InvalidSnapshot();
        }
        input = input[3];
      } else if (event.read<String>('kind') == 'reversal') {
        throw const InvalidSnapshot();
      } else if (input.first == 'refund-posting-v1') {
        if (!refundsAware ||
            input.length != 5 ||
            input[1] != refundLinks[(ws, resultId)] ||
            event.read<String>('kind') != 'refund' ||
            jsonEncode(input[2]) !=
                jsonEncode(
                  Money(
                    Currency(
                      event.read<String>('currency'),
                      event.read<int>('scale'),
                    ),
                    -BigInt.from(event.read<int>('expense')),
                  ).toJson(),
                ) ||
            (context == null
                ? input[4] != null
                : jsonEncode(input[4]) != context) ||
            input[3] is! List ||
            (input[3] as List).isEmpty) {
          throw const InvalidSnapshot();
        }
        input = input[3];
      } else if (event.read<String>('kind') == 'refund') {
        throw const InvalidSnapshot();
      } else if (input.first == 'fx-posting-v1') {
        if (input.length != 3 ||
            context == null ||
            jsonEncode(input[2]) != context ||
            input[1] is! List ||
            (input[1] as List).isEmpty ||
            input[1][0] != 'posting-v1')
          throw const InvalidSnapshot();
        input = input[1];
      } else if (context != null) {
        throw const InvalidSnapshot();
      }
      final isCreate = input.first == 'create-v1';
      if (isCreate &&
          (input.length != 4 ||
              input[2] is! Map ||
              event.read<String>('kind') != 'opening'))
        throw const InvalidSnapshot();
      final posting = isCreate ? input[3] : input;
      final eventLegs = legsByEvent[(ws, resultId)] ?? const <QueryRow>[];
      final eventAllocations =
          allocationsByEvent[(ws, resultId)] ?? <String, QueryRow>{};
      final versioned = input.first == 'posting-v2';
      if (posting is! List ||
          posting.length != (versioned ? 5 : 3 + eventLegs.length) ||
          posting[0] != (versioned ? 'posting-v2' : 'posting-v1') ||
          posting[1] != event.read<String>('kind') ||
          posting[2] != event.read<String>('business_date') ||
          auditKind != (isCreate ? 'account.open' : 'ledger.${posting[1]}'))
        throw const InvalidSnapshot();
      if (versioned) {
        if (posting[3] is! List ||
            (posting[3] as List).length != eventLegs.length ||
            posting[4] is! List ||
            (posting[4] as List).length != eventAllocations.length ||
            eventAllocations.isEmpty)
          throw const InvalidSnapshot();
        final seen = <String>{};
        for (final encoded in posting[4] as List) {
          if (encoded is! List ||
              encoded.length != 3 ||
              encoded[0] is! String ||
              !seen.add(encoded[0] as String) ||
              encoded[1] is! int) {
            throw const InvalidSnapshot();
          }
          final allocation = eventAllocations[encoded[0]];
          if (allocation == null ||
              encoded[1] != allocation.read<int>('category_version') ||
              jsonEncode(encoded[2]) !=
                  jsonEncode(
                    Money(
                      Currency(
                        event.read<String>('currency'),
                        event.read<int>('scale'),
                      ),
                      BigInt.from(allocation.read<int>('amount')),
                    ).toJson(),
                  )) {
            throw const InvalidSnapshot();
          }
        }
      } else if (eventAllocations.isNotEmpty) {
        throw const InvalidSnapshot();
      }
      if (isCreate &&
          (input[1] != eventLegs.single.read<String>('account_id') ||
              input[2]['openedOn'] != posting[2] ||
              input[2]['version'] != 1 ||
              input[2]['state'] != 'active'))
        throw const InvalidSnapshot();
      for (var i = 0; i < eventLegs.length; i++) {
        final leg = eventLegs[i];
        final encoded = versioned ? posting[3][i] : posting[i + 3];
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
    if (categoryOperations.isNotEmpty ||
        tagOperations.isNotEmpty ||
        merchantOperations.isNotEmpty)
      throw const InvalidSnapshot();
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
