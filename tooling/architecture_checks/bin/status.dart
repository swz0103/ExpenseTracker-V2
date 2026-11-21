import 'dart:io';

import 'package:architecture_checks/app_syntax.dart';
import 'package:path/path.dart' as p;

/// The figures of docs/roadmap.md's 現況 table, measured rather than copied
/// by hand. Run from anywhere after the app's `flutter test --coverage`:
///
///     dart run tooling/architecture_checks/bin/status.dart
///
/// Prints a Markdown table, each figure with how it was measured, and
/// adds it to the run's summary on CI.
void main() {
  final root = p.normalize(
    p.join(p.dirname(Platform.script.toFilePath()), '..', '..', '..'),
  );
  final app = p.join(root, 'apps', 'expense_tracker');
  List<File> dart(String dir, {String end = '.dart'}) => [
    for (final f in Directory(p.join(app, dir)).listSync(recursive: true))
      if (f is File && f.path.endsWith(end)) f,
  ];

  final lib = dart('lib');
  final lines = lib.fold(0, (n, f) => n + f.readAsLinesSync().length);
  final tests = dart('test', end: '_test.dart').length;
  final units = appUnits(root);
  final casts = [for (final u in units.values) ...Casts().run(u)].length;
  final whole = wholeLedgerFiles(units).length;
  final checks = p.join(root, 'tooling', 'architecture_checks');
  final debt = RegExp(r"^  'src/[^']+':", multiLine: true)
      .allMatches(
        _between(
          File(p.join(checks, 'test', 'code_size_test.dart'))
              .readAsStringSync(),
          'const longerFunctions',
          '};',
        ),
      )
      .length;
  final uncovered = File(p.join(checks, 'uncovered.txt'))
      .readAsLinesSync()
      .where((l) => l.trim().isNotEmpty && !l.startsWith('#'))
      .length;

  final rows = [
    ('程式', '${lib.length} 個檔、${_digits(lines)} 行', 'lib 底下的 .dart'),
    ('測試檔', '$tests 個', 'test 底下的 *_test.dart'),
    (
      '行覆蓋率',
      _coverage(File(p.join(app, 'coverage', 'lcov.info'))),
      'flutter test --coverage 的 lcov；沒有測試載入的檔不在其中，看下一列',
    ),
    ('從未執行的類別與函式', '$uncovered 個', 'uncovered.txt，只准變少'),
    ('超過 80 行的函式', '$debt 個', 'code_size_test 的債務清單'),
    ('依賴整個 Ledger', '$whole 個檔', '功能裡提到 Ledger 的檔（語法樹；app/ 是組裝點，不算）'),
    ('轉成基本型別', '$casts 處', '`as Map`、`as String` 等（語法樹）'),
  ];
  final table = StringBuffer()
    ..writeln('| 項目 | 數字 | 量法 |')
    ..writeln('| --- | --- | --- |');
  for (final (what, figure, how) in rows) {
    table.writeln('| $what | $figure | $how |');
  }
  stdout.write(table);
  final summary = Platform.environment['GITHUB_STEP_SUMMARY'];
  if (summary != null) {
    File(summary)
        .writeAsStringSync('### 現況\n\n$table\n', mode: FileMode.append);
  }
}

String _between(String text, String from, String to) {
  final start = text.indexOf(from);
  return text.substring(start, text.indexOf(to, start));
}

String _coverage(File lcov) {
  if (!lcov.existsSync()) return '（沒有 lcov）';
  var run = 0, all = 0;
  for (final line in lcov.readAsLinesSync()) {
    if (!line.startsWith('DA:')) continue;
    all++;
    if (!line.endsWith(',0')) run++;
  }
  return '${(run * 1000 ~/ all) / 10}%';
}

String _digits(int n) =>
    n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+$)'), (_) => ',');
