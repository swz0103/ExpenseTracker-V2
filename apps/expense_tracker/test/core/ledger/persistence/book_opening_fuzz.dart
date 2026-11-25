import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:expense_tracker/src/core/ledger/persistence/book_opening.dart';
import 'package:expense_tracker/src/core/ledger/persistence/codec/record_json.dart';
import 'package:expense_tracker/src/core/ledger/persistence/codec/record_shape.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storage/storage.dart';

/// R12, run by book_opening_test.dart: the books kept by every released
/// version, their rows mutated at random (seeded), opened. Reading never throws, every row is read or
/// set aside, and nothing read breaks restore's shape rules. A few
/// hundred cases here; `FUZZ_CASES=3000` for a nightly run.
void bookOpeningFuzz() {
  final cases = int.tryParse(Platform.environment['FUZZ_CASES'] ?? '') ?? 300;
  const shelfOf = {
    'accounts': 'account',
    'categories': 'category',
    'entries': 'entry',
    'budgets': 'budget',
    'recurring': 'recurring',
    'trash': 'trash',
  };

  final fixtures = [
    for (final d in Directory(
      'test/fixtures/books',
    ).listSync().whereType<Directory>())
      jsonDecode(File('${d.path}/records.json').readAsStringSync())
          as Map<String, Object?>,
  ];

  List<StoredRow> rowsOf(Map<String, Object?> fixture) {
    final rows = <StoredRow>[];
    var seq = 1;
    for (final MapEntry(key: name, value: shelf) in shelfOf.entries) {
      for (final (i, body) in (fixture[name] as List? ?? const []).indexed) {
        final json = jsonDecode(body as String) as Map<String, Object?>;
        final id = (json['id'] ?? json['category'] ?? 'x$i') as String;
        rows.add(StoredRow(seq++, shelf, id, body));
      }
    }
    return rows;
  }

  const pool = <Object?>[
    null, true, false, 0, -1, 1, 2, 40, 99999999999, //
    9223372036854775807, -9223372036854775807, 1.5, 1e300, -0.0, //
    'x', '', '2026-13-01', '0000-00-00', '9999-12-31', '2026-02-30', //
    '\u0000', '😀', [], {}, [null], {'a': 1}, 'expense', 'buy', 'sell',
  ];

  Object? mutateJson(Random r, Object? v) {
    if (v is Map<String, Object?>) {
      final m = Map<String, Object?>.of(v);
      if (m.isEmpty || r.nextInt(5) == 0) {
        m['zz${r.nextInt(5)}'] = pool[r.nextInt(pool.length)];
        return m;
      }
      final k = m.keys.elementAt(r.nextInt(m.length));
      switch (r.nextInt(4)) {
        case 0:
          m.remove(k);
        case 1:
          m[k] = pool[r.nextInt(pool.length)];
        default:
          m[k] = mutateJson(r, m[k]);
      }
      return m;
    }
    if (v is List<Object?>) {
      final l = List<Object?>.of(v);
      if (l.isEmpty || r.nextInt(4) == 0) {
        return l..add(pool[r.nextInt(pool.length)]);
      }
      final i = r.nextInt(l.length);
      if (r.nextBool()) {
        l[i] = mutateJson(r, l[i]);
      } else {
        l.removeAt(i);
      }
      return l;
    }
    return r.nextInt(3) == 0 ? pool[r.nextInt(pool.length)] : v;
  }

  String mutateText(Random r, String s) {
    var t = s;
    for (var k = 0; k < 1 + r.nextInt(3) && t.isNotEmpty; k++) {
      final at = r.nextInt(t.length);
      const bits = ['{', '}', '[', ']', '"', ',', ':', 'null', '1e999', '-'];
      t = switch (r.nextInt(4)) {
        0 => t.substring(0, at),
        1 => t.substring(0, at) + t.substring(at + 1),
        2 =>
          t.substring(0, at) +
              String.fromCharCode(r.nextInt(0x600)) +
              t.substring(at),
        _ =>
          t.substring(0, at) + bits[r.nextInt(bits.length)] + t.substring(at),
      };
    }
    return t;
  }

  test('$cases mutated books: every row read or set aside, none throws', () {
    final r = Random(777);
    for (var iteration = 0; iteration < cases; iteration++) {
      final rows = [
        for (final row in rowsOf(fixtures[r.nextInt(fixtures.length)]))
          if (r.nextInt(4) != 0)
            row
          else
            StoredRow(
              row.seq,
              row.shelf,
              row.id,
              r.nextBool()
                  ? jsonEncode(mutateJson(r, jsonDecode(row.body)))
                  : mutateText(r, row.body),
            ),
      ];
      final DecodedBook book;
      try {
        book = decodeBook(
          shelvesOf(rows),
          trashFrom: DateTime.utc(2026, 1, 1),
          today: DateTime.utc(2026, 10, 4),
        );
      } on Object catch (error) {
        fail('case $iteration threw $error');
      }
      final read =
          book.accounts.length +
          book.categories.length +
          book.entries.length +
          book.budgets.length +
          book.recurring.length +
          book.trash.length;
      final expired = book.expired.where((c) => c.shelf == 'trash').length;
      // A mutated id can repeat another's, which the shelf keeps once.
      final distinct = {for (final row in rows) '${row.shelf}/${row.id}'};
      expect(
        read + book.aside.length + expired,
        greaterThanOrEqualTo(distinct.length),
        reason: 'case $iteration lost a row',
      );
      for (final Object record in [
        ...book.accounts,
        ...book.entries,
        ...book.budgets,
        ...book.recurring,
        ...book.trash,
      ]) {
        expect(shapeIssues(record), isEmpty, reason: 'case $iteration');
      }
      for (final e in book.entries) {
        // What was read writes back and reads back the same.
        final back = entryFromJson(
          jsonDecode(jsonEncode(entryToJson(e))) as Map<String, Object?>,
        );
        expect((back.amount, back.date), (e.amount, e.date));
      }
    }
  });
}
