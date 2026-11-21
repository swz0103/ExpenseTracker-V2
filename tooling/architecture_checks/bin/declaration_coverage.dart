import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:path/path.dart' as p;

/// Coverage by class and top-level function rather than by file: a file's
/// average hides a class nothing runs (the merchant and tag pickers sat at
/// 0% inside a 609-line file at 70%). Run from the app after
/// `flutter test --coverage`:
///
///     dart run ../../tooling/architecture_checks/bin/declaration_coverage.dart
///
/// Prints the declarations under half covered, and fails when one of at
/// least [smallest] executable lines is not run at all and is not in
/// [knownFile]; or when one listed there has since been covered, so the
/// list only shrinks.
const smallest = 10;
const knownFile = 'tooling/architecture_checks/uncovered.txt';

void main(List<String> args) {
  final app = Directory.current.path;
  final root = p.normalize(p.join(app, '..', '..'));
  final hits = _hits(File(p.join(app, 'coverage', 'lcov.info')));
  final rows = <(String, int, int)>[];
  // A file no test loads is not in the lcov at all: every line of it
  // counts as not run, rather than the file not counting.
  final files = [
    for (final f in Directory(p.join(app, 'lib')).listSync(recursive: true))
      if (f is File && f.path.endsWith('.dart'))
        p.relative(f.path, from: app).replaceAll(r'\', '/'),
  ];
  for (final path in files) {
    final file = File(p.join(app, path));
    final lines = hits[path];
    final unit = parseString(
      content: file.readAsStringSync(),
      throwIfDiagnostics: false,
    ).unit;
    for (final d in unit.declarations) {
      final name = _name(d);
      if (name == null) continue;
      final first = unit.lineInfo.getLocation(d.offset).lineNumber;
      final last = unit.lineInfo.getLocation(d.end).lineNumber;
      var run = 0, all = 0;
      // Only what has code to run, the bodies of its functions: constants
      // and abstract members have none, which is also why the lcov leaves
      // such a file out. The declaration's own lines, such as a const
      // constructor, count as run when the file is merely loaded, so they
      // do not count.
      final bodies = _Bodies();
      d.accept(bodies);
      if (lines == null) {
        if (bodies.lines > 0) {
          rows.add(('${path.substring(4)}::$name', 0, bodies.lines));
        }
        continue;
      }
      for (final MapEntry(key: line, value: count) in lines.entries) {
        if (line < first || line > last || !bodies.holds(line)) continue;
        all++;
        if (count > 0) run++;
      }
      if (all > 0) rows.add(('${path.substring(4)}::$name', run, all));
    }
  }
  rows.sort((a, b) => (a.$2 / a.$3).compareTo(b.$2 / b.$3));

  final known = File(p.join(root, knownFile))
      .readAsLinesSync()
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty && !l.startsWith('#'))
      .toSet();
  final none = {
    for (final (name, run, all) in rows)
      if (run == 0 && all >= smallest) name,
  };
  final fresh = none.difference(known);
  final covered = known.difference(none);

  final report = StringBuffer()
    ..writeln('| 宣告 | 覆蓋 | 可執行行 |')
    ..writeln('| --- | --- | --- |');
  for (final (name, run, all) in rows) {
    if (all < smallest || run * 2 >= all) continue;
    report.writeln('| `$name` | ${run * 100 ~/ all}% | $all |');
  }
  stdout.write(report);
  final summary = Platform.environment['GITHUB_STEP_SUMMARY'];
  if (summary != null) {
    File(
      summary,
    ).writeAsStringSync('### 覆蓋不到一半的類別與函式\n\n$report\n', mode: FileMode.append);
  }
  for (final name in fresh) {
    stderr.writeln('$name is never run by a test: test it');
  }
  for (final name in covered) {
    stderr.writeln('$name is run now (or gone): take it off $knownFile');
  }
  if (fresh.isNotEmpty || covered.isNotEmpty) exitCode = 1;
}

/// lib path → line → hits, from an lcov file.
Map<String, Map<int, int>> _hits(File lcov) {
  final hits = <String, Map<int, int>>{};
  Map<int, int>? current;
  for (final line in lcov.readAsLinesSync()) {
    if (line.startsWith('SF:')) {
      final path = line.substring(3).replaceAll(r'\', '/');
      current = hits[path.substring(path.indexOf('lib/'))] = {};
    } else if (line.startsWith('DA:') && current != null) {
      final [at, count, ...] = line.substring(3).split(',');
      current[int.parse(at)] = int.parse(count);
    }
  }
  return hits;
}

String? _name(CompilationUnitMember d) => switch (d) {
  ClassDeclaration() => d.namePart.typeName.lexeme,
  MixinDeclaration(:final name) => name.lexeme,
  ExtensionDeclaration(:final name?) => name.lexeme,
  FunctionDeclaration(:final name) => name.lexeme,
  _ => null,
};

/// The lines of the bodies of code in a declaration, outermost only.
final class _Bodies extends RecursiveAstVisitor<void> {
  var lines = 0;

  /// The first and last line of each body.
  final _ranges = <(int, int)>[];

  /// Whether [line] is inside one of the bodies.
  bool holds(int line) => _ranges.any((r) => line >= r.$1 && line <= r.$2);

  @override
  void visitBlockFunctionBody(BlockFunctionBody node) => _count(node);

  @override
  void visitExpressionFunctionBody(ExpressionFunctionBody node) => _count(node);

  void _count(FunctionBody node) {
    final info = (node.root as CompilationUnit).lineInfo;
    final first = info.getLocation(node.offset).lineNumber;
    final last = info.getLocation(node.end).lineNumber;
    lines += last - first + 1;
    _ranges.add((first, last));
  }
}
