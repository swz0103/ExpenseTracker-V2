import 'dart:convert';
import 'dart:io';

import 'package:foundation_values/foundation_values.dart';
import 'package:modular_persistence_probe/database.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:validated_restore_probe/snapshot.dart';

Object? yen(Object? input) {
  if (input is List) return input.map(yen).toList();
  if (input is Map)
    return {
      for (final entry in input.entries)
        entry.key: entry.key == 'currency'
            ? 'JPY'
            : entry.key == 'scale'
            ? 0
            : yen(entry.value),
    };
  return input;
}

void main() {
  final root = Directory('.dart_tool/validation-index-tests')
    ..createSync(recursive: true);
  late Directory work;
  late Map<String, dynamic> snapshot;
  setUp(() async {
    work = root.createTempSync('case-');
    final source = File('${work.path}/source.db');
    final raw = sqlite3.open(source.path);
    raw.execute(
      File('../modular_persistence/test/fixtures/v1.sql').readAsStringSync(),
    );
    raw.close();
    final db = ProbeDatabase(source);
    try {
      snapshot = jsonDecode(
        utf8.decode(await SnapshotCodec().capture(db)),
      ) as Map<String, dynamic>;
    } finally {
      await db.close();
    }
  });
  tearDown(() {
    if (!work.absolute.path.startsWith(
      '${root.absolute.path}${Platform.pathSeparator}',
    ))
      throw StateError('unsafe cleanup');
    work.deleteSync(recursive: true);
  });
  test('validation indexes retain workspace in keys with identical public IDs and different currencies', () async {
    final tables = snapshot['tables'] as Map;
    final workspace = PublicId.generate().value;
    for (final values in tables.values) {
      final rows = values as List;
      final copies = <Object>[];
      for (final value in rows) {
        final row = jsonDecode(jsonEncode(value)) as Map;
        row['workspace'] = workspace;
        if (row.containsKey('currency')) row['currency'] = 'JPY';
        if (row.containsKey('scale')) row['scale'] = '0';
        for (final name in ['input', 'payload']) {
          if (row.containsKey(name))
            row[name] = jsonEncode(yen(jsonDecode(row[name] as String)));
        }
        copies.add(row);
      }
      rows.addAll(copies);
    }
    final bytes = utf8.encode(jsonEncode(snapshot));
    final file = File('${work.path}/target.db');
    await SnapshotCodec().stage(bytes, file);
    final db = ProbeDatabase(file);
    try {
      expect(await SnapshotCodec().capture(db), bytes);
    } finally {
      await db.close();
    }
  });
  test(
    'grouped receipt check still rejects two receipts for one event',
    () async {
      final tables = snapshot['tables'] as Map;
      final receipts = tables['receipts'] as List;
      final audit = tables['audit'] as List;
      final operation = PublicId.generate().value;
      receipts.add({...receipts.last as Map, 'operation_id': operation});
      audit.add({...audit.last as Map, 'operation_id': operation});
      await expectLater(
        SnapshotCodec().stage(
          utf8.encode(jsonEncode(snapshot)),
          File('${work.path}/target.db'),
        ),
        throwsA(isA<InvalidSnapshot>()),
      );
    },
  );
  test('missing event receipt still fails grouped cardinality check', () async {
    final tables = snapshot['tables'] as Map;
    (tables['receipts'] as List).removeLast();
    (tables['audit'] as List).removeLast();
    await expectLater(
      SnapshotCodec().stage(
        utf8.encode(jsonEncode(snapshot)),
        File('${work.path}/target.db'),
      ),
      throwsA(isA<InvalidSnapshot>()),
    );
  });
}
