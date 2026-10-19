import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Every package: a test must say which failure it expects;
/// `throwsA(anything)` passes for a crash too (health check G1-15).
const strictPackages = [
  'apps/expense_tracker',
  'infrastructure/market',
  'infrastructure/storage',
  'infrastructure/vault',
  'packages/core',
  'packages/domain',
];

final _vague = RegExp(r'throwsA\(\s*(anything|isA<(Object|Exception)>\(\))');

void main() {
  test('tests in new packages name the failure they expect', () {
    final root = p.normalize(p.join(Directory.current.path, '..', '..'));
    final offenders = <String>[];
    for (final package in strictPackages) {
      final tests = Directory(p.join(root, package, 'test'));
      if (!tests.existsSync()) continue;
      for (final file in tests.listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.dart')) continue;
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (_vague.hasMatch(lines[i])) {
            offenders.add('${p.relative(file.path, from: root)}:${i + 1}');
          }
        }
      }
    }
    expect(offenders, isEmpty);
  });
}
