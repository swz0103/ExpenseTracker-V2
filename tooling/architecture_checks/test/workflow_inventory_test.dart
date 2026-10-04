import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  test('bounded integration workflow covers every registered host package', () {
    final root = p.normalize(p.join(Directory.current.path, '..', '..'));
    final script = File(p.join(root, 'tooling', 'run-host-checks.ps1'))
        .readAsStringSync();
    final workflow = File(
      p.join(root, '.github', 'workflows', 'integration-validation.yml'),
    ).readAsStringSync();
    final registered = RegExp(r"Path = '([^']+)'")
        .allMatches(script)
        .map((m) => m.group(1)!)
        .toSet();
    final covered = RegExp(
      r"(?:-Package |')((?:apps|packages|infrastructure|tooling)/[a-z_]+)'?",
    ).allMatches(workflow).map((m) => m.group(1)!).toSet();
    expect(covered, registered);

    final yaml = loadYaml(workflow) as YamlMap;
    final triggers = yaml['on'] as YamlMap;
    final push = triggers['push'] as YamlMap;
    final branches = push['branches'] as YamlList;
    expect(branches, hasLength(1));
    expect(branches.first, 'main');
    expect(
      push['paths'],
      containsAll([
        '.github/workflows/**',
        'apps/**',
        'architecture/**',
        'infrastructure/**',
        'packages/**',
        'tooling/**',
      ]),
    );
    final pullRequest = triggers['pull_request'] as YamlMap;
    expect(pullRequest['branches'], contains('main'));
    final jobs = yaml['jobs'] as YamlMap;
    expect(jobs.length, 4);
    final maxMinutes = jobs.values.fold<int>(
      0,
      (total, job) => total + (job['timeout-minutes'] as int),
    );
    expect(maxMinutes, lessThanOrEqualTo(68));
    for (final job in jobs.values) {
      expect(job['runs-on'], 'ubuntu-latest');
    }
  });

  test('every package on disk is checked by the host script', () {
    final root = p.normalize(p.join(Directory.current.path, '..', '..'));
    final script = File(p.join(root, 'tooling', 'run-host-checks.ps1'))
        .readAsStringSync();
    final registered = RegExp(r"Path = '([^']+)'")
        .allMatches(script)
        .map((m) => m.group(1)!)
        .toSet();
    final onDisk = <String>{};
    for (final folder in ['apps', 'packages', 'infrastructure', 'tooling']) {
      final location = Directory(p.join(root, folder));
      if (!location.existsSync()) continue;
      for (final entity in location.listSync()) {
        if (entity is! Directory) continue;
        if (File(p.join(entity.path, 'pubspec.yaml')).existsSync()) {
          final relative = p.relative(entity.path, from: root);
          onDisk.add(p.posix.joinAll(p.split(relative)));
        }
      }
    }
    // A package left out of the script would never be analyzed or tested
    // (health check G1-15).
    expect(registered, onDisk);
  });
}
