import 'dart:convert';
import 'dart:io';

import 'package:architecture_checks/coverage_floors.dart';
import 'package:path/path.dart' as p;

/// Holds each package's line coverage to its floor in
/// tooling/coverage_floors.json. Run after the package's tests wrote
/// `coverage/lcov.info` (`dart test --coverage-path=coverage/lcov.info`, or
/// `flutter test --coverage` for the app):
///
///     dart run tooling/architecture_checks/bin/check_coverage.dart [package...]
///
/// With no package named, every package of the floors file is checked. Run
/// from anywhere; paths are relative to the repository root.
void main(List<String> args) {
  final root = p.normalize(
    p.join(p.dirname(Platform.script.toFilePath()), '..', '..', '..'),
  );
  final file = File(p.join(root, 'tooling', 'coverage_floors.json'));
  final floors = <String, int>{
    for (final e in (jsonDecode(
      file.readAsStringSync(),
    ) as Map<String, dynamic>).entries)
      e.key: e.value as int,
  };
  final unknown = args.where((a) => !floors.containsKey(a)).toList();
  if (unknown.isNotEmpty) {
    stderr.writeln('No floor set for: ${unknown.join(', ')}');
    exit(2);
  }
  final selected = args.isEmpty
      ? floors
      : {for (final a in args) a: floors[a]!};
  final measured = <String, double?>{
    for (final package in selected.keys)
      package: _percent(File(p.join(root, package, 'coverage', 'lcov.info'))),
  };
  final results = checkFloors(selected, measured);
  for (final result in results) {
    stdout.writeln('${result.failed ? 'FAIL' : 'ok  '} $result');
  }
  if (results.any((r) => r.failed)) exit(1);
}

double? _percent(File lcov) =>
    lcov.existsSync() ? parseLcov(lcov.readAsStringSync()).percent : null;
