// Keeps STATUS.md and the skipped tests of this folder in step: every
// skipped id is listed there with its package and file, and none is
// recorded as a test that passes when enabled (such a test would not
// detect its defect).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// One row of the table in STATUS.md.
typedef Row = ({String id, String package, String file, String fails});

void main() {
  const folder = 'test/known_defects';
  final mark = RegExp(r"knownDefect\('([^']+)',\s*'([^']+)'\)");

  /// The ids marked in the test files, with their package and file.
  Map<String, (String, String)> marked() {
    final found = <String, (String, String)>{};
    for (final file in Directory(folder).listSync()) {
      if (file is! File) continue;
      final name = file.uri.pathSegments.last;
      if (!name.endsWith('_test.dart') || name == 'registry_test.dart') {
        continue;
      }
      for (final m in mark.allMatches(file.readAsStringSync())) {
        found[m[1]!] = (m[2]!, name);
      }
    }
    return found;
  }

  List<Row> table() {
    final rows = <Row>[];
    for (final line in File('$folder/STATUS.md').readAsLinesSync()) {
      if (!line.startsWith('|')) continue;
      final cells = [for (final c in line.split('|').skip(1)) c.trim()];
      // Header and separator rows have no id of the form ABC-12 or F12.
      if (!RegExp(r'^([A-Z]{2,4}-\d+|F\d+)$').hasMatch(cells[0])) continue;
      rows.add((
        id: cells[0],
        package: cells[1],
        file: cells[2],
        fails: cells[3],
      ));
    }
    return rows;
  }

  test('every skipped known defect is listed in STATUS.md', () {
    final listed = {for (final r in table()) r.id: r};
    final faults = <String>[];
    for (final MapEntry(key: id, value: (package, file)) in marked().entries) {
      final row = listed[id];
      if (row == null) {
        faults.add('$id is not in STATUS.md');
      } else if (row.package != package || row.file != file) {
        faults.add(
          '$id: STATUS.md says ${row.package} ${row.file}, '
          'the test says $package $file',
        );
      }
    }
    expect(faults, isEmpty, reason: faults.join('\n'));
  });

  test('STATUS.md lists no id without a test', () {
    final tests = marked();
    final faults = [
      for (final r in table())
        if (!tests.containsKey(r.id)) '${r.id} has no skipped test',
    ];
    expect(faults, isEmpty, reason: faults.join('\n'));
  });

  test('no row says its test passes when enabled', () {
    final rows = table();
    expect(rows, isNotEmpty);
    final faults = [
      for (final r in rows)
        if (r.fails != 'yes') '${r.id}: fails-when-enabled is "${r.fails}"',
    ];
    expect(faults, isEmpty, reason: faults.join('\n'));
  });
}
