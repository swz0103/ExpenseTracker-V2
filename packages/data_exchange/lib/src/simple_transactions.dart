import 'dart:convert';

import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';

/// A narrow, loss-declared interchange format. It is not a restorable backup.
/// Importing these facts into a Ledger is a separate, confirmed use case.
final class SimpleTransactionBatch {
  SimpleTransactionBatch(this.sourceWorkspace, Iterable<SimpleTransaction> rows)
    : records = List.unmodifiable(rows) {
    if (records.length > maxRecords) {
      throw const ExchangeException('too_many_records');
    }
    final ids = <PublicId>{};
    for (var i = 0; i < records.length; i++) {
      if (!ids.add(records[i].sourceRecordId)) {
        throw ExchangeException('duplicate_source_record', i + 1);
      }
    }
  }

  static const maxRecords = 5000;
  final WorkspaceId sourceWorkspace;
  final List<SimpleTransaction> records;
}

/// Only ordinary income and expense facts are admitted by format version 1.
final class SimpleTransaction {
  SimpleTransaction({
    required this.sourceRecordId,
    required this.date,
    required this.kind,
    required this.accountId,
    required this.amount,
    this.note = '',
  }) {
    if (kind != PostingKind.income && kind != PostingKind.expense) {
      throw const ExchangeException('unsupported_kind');
    }
    if (amount.minorUnits <= BigInt.zero) {
      throw const ExchangeException('non_positive_amount');
    }
    if (utf8.encode(note).length > 4096) {
      throw const ExchangeException('note_too_long');
    }
  }

  final PublicId sourceRecordId;
  final BusinessDate date;
  final PostingKind kind;
  final PublicId accountId;
  final Money amount;
  final String note;
}

final class ExchangeException implements Exception {
  const ExchangeException(this.code, [this.row]);
  final String code;
  final int? row;

  @override
  String toString() =>
      'ExchangeException($code${row == null ? '' : ', row $row'})';
}

/// The same versioned facts can be exchanged as JSON or RFC 4180-style CSV.
/// CSV's note_json cell begins with a literal JSON quote rather than a user's
/// leading formula marker. Third-party spreadsheet behavior is not guaranteed.
abstract final class SimpleTransactionCodec {
  static const format = 'expensetracker-v2-simple-transactions';
  static const version = 1;
  static const maxBytes = 24 * 1024 * 1024;
  static const _jsonKeys = {
    'sourceRecordId',
    'date',
    'kind',
    'accountId',
    'currency',
    'scale',
    'minorUnits',
    'note',
  };
  static const _csvHeader = [
    'format',
    'version',
    'source_workspace',
    'source_record_id',
    'date',
    'kind',
    'account_id',
    'currency',
    'scale',
    'minor_units',
    'note_json',
  ];

  static String encodeJson(SimpleTransactionBatch batch) => _bounded(
    jsonEncode({
      'format': format,
      'version': version,
      'sourceWorkspace': batch.sourceWorkspace.toString(),
      'records': [
        for (final row in batch.records)
          {
            'sourceRecordId': row.sourceRecordId.value,
            'date': row.date.toString(),
            'kind': row.kind.name,
            'accountId': row.accountId.value,
            'currency': row.amount.currency.code,
            'scale': row.amount.currency.scale,
            'minorUnits': row.amount.minorUnits.toString(),
            'note': row.note,
          },
      ],
    }),
  );

  static SimpleTransactionBatch decodeJson(String input) {
    _checkSize(input);
    try {
      final decoded = jsonDecode(input);
      if (decoded is! Map<String, dynamic> ||
          decoded.keys.toSet().difference({
            'format',
            'version',
            'sourceWorkspace',
            'records',
          }).isNotEmpty ||
          decoded['format'] != format ||
          decoded['version'] != version ||
          decoded['sourceWorkspace'] is! String ||
          decoded['records'] is! List) {
        throw const ExchangeException('invalid_header');
      }
      final raw = decoded['records'] as List;
      if (raw.length > SimpleTransactionBatch.maxRecords) {
        throw const ExchangeException('too_many_records');
      }
      return SimpleTransactionBatch(
        WorkspaceId.parse(decoded['sourceWorkspace'] as String),
        [for (var i = 0; i < raw.length; i++) _decodeMap(raw[i], i + 1)],
      );
    } on ExchangeException {
      rethrow;
    } catch (_) {
      throw const ExchangeException('invalid_document');
    }
  }

  static String encodeCsv(SimpleTransactionBatch batch) {
    if (batch.records.isEmpty) {
      throw const ExchangeException('empty_csv_without_workspace');
    }
    final rows = <List<String>>[
      _csvHeader,
      for (final row in batch.records)
        [
          format,
          '$version',
          batch.sourceWorkspace.toString(),
          row.sourceRecordId.value,
          row.date.toString(),
          row.kind.name,
          row.accountId.value,
          row.amount.currency.code,
          '${row.amount.currency.scale}',
          row.amount.minorUnits.toString(),
          jsonEncode(row.note),
        ],
    ];
    return _bounded(
      '${rows.map((r) => r.map(_csvEscape).join(',')).join('\r\n')}\r\n',
    );
  }

  static SimpleTransactionBatch decodeCsv(String input) {
    _checkSize(input);
    final rows = _readCsv(input);
    if (rows.isEmpty || !_same(rows.first, _csvHeader)) {
      throw const ExchangeException('invalid_header');
    }
    if (rows.length - 1 > SimpleTransactionBatch.maxRecords) {
      throw const ExchangeException('too_many_records');
    }
    WorkspaceId? workspace;
    final records = <SimpleTransaction>[];
    for (var i = 1; i < rows.length; i++) {
      final values = rows[i];
      if (values.length != _csvHeader.length ||
          values[0] != format ||
          values[1] != '$version') {
        throw ExchangeException('invalid_row', i);
      }
      try {
        final rowWorkspace = WorkspaceId.parse(values[2]);
        if (workspace != null && rowWorkspace != workspace) {
          throw ExchangeException('mixed_workspace', i);
        }
        workspace = rowWorkspace;
        final note = jsonDecode(values[10]);
        if (note is! String) throw ExchangeException('invalid_note', i);
        records.add(
          _decodeMap({
            'sourceRecordId': values[3],
            'date': values[4],
            'kind': values[5],
            'accountId': values[6],
            'currency': values[7],
            'scale': int.parse(values[8]),
            'minorUnits': values[9],
            'note': note,
          }, i),
        );
      } on ExchangeException {
        rethrow;
      } catch (_) {
        throw ExchangeException('invalid_row', i);
      }
    }
    if (workspace == null) {
      throw const ExchangeException('empty_csv_without_workspace');
    }
    return SimpleTransactionBatch(workspace, records);
  }

  static SimpleTransaction _decodeMap(Object? value, int row) {
    if (value is! Map<String, dynamic> ||
        value.keys.toSet().difference(_jsonKeys).isNotEmpty ||
        value['sourceRecordId'] is! String ||
        value['date'] is! String ||
        value['kind'] is! String ||
        value['accountId'] is! String ||
        value['currency'] is! String ||
        value['scale'] is! int ||
        value['minorUnits'] is! String ||
        value['note'] is! String) {
      throw ExchangeException('invalid_row', row);
    }
    try {
      return SimpleTransaction(
        sourceRecordId: PublicId.parse(value['sourceRecordId'] as String),
        date: BusinessDate.parse(value['date'] as String),
        kind: PostingKind.values.byName(value['kind'] as String),
        accountId: PublicId.parse(value['accountId'] as String),
        amount: Money(
          Currency(value['currency'] as String, value['scale'] as int),
          BigInt.parse(value['minorUnits'] as String),
        ),
        note: value['note'] as String,
      );
    } on ExchangeException catch (error) {
      throw ExchangeException(error.code, error.row ?? row);
    } catch (_) {
      throw ExchangeException('invalid_row', row);
    }
  }

  static void _checkSize(String input) {
    if (utf8.encode(input).length > maxBytes) {
      throw const ExchangeException('too_large');
    }
  }

  static String _bounded(String output) {
    _checkSize(output);
    return output;
  }

  static bool _same(List<String> a, List<String> b) =>
      a.length == b.length &&
      [for (var i = 0; i < a.length; i++) a[i] == b[i]].every((e) => e);

  static String _csvEscape(String value) => value.contains(RegExp('[,"\r\n]'))
      ? '"${value.replaceAll('"', '""')}"'
      : value;

  static List<List<String>> _readCsv(String input) {
    final rows = <List<String>>[];
    var row = <String>[];
    var field = StringBuffer();
    var quoted = false;
    var closedQuote = false;
    void addField() {
      row.add(field.toString());
      field = StringBuffer();
      closedQuote = false;
    }

    void addRow() {
      addField();
      rows.add(row);
      row = <String>[];
    }

    for (var i = 0; i < input.length; i++) {
      final char = input[i];
      if (quoted) {
        if (char == '"') {
          if (i + 1 < input.length && input[i + 1] == '"') {
            field.write('"');
            i++;
          } else {
            quoted = false;
            closedQuote = true;
          }
        } else {
          field.write(char);
        }
      } else if (char == '"' && field.isEmpty && !closedQuote) {
        quoted = true;
      } else if (char == ',') {
        addField();
      } else if (char == '\n' || char == '\r') {
        if (char == '\r' && i + 1 < input.length && input[i + 1] == '\n') i++;
        addRow();
      } else if (closedQuote || char == '"') {
        throw ExchangeException('invalid_csv', rows.length + 1);
      } else {
        field.write(char);
      }
    }
    if (quoted) throw ExchangeException('invalid_csv', rows.length + 1);
    if (field.isNotEmpty || row.isNotEmpty || closedQuote) addRow();
    return rows;
  }
}
