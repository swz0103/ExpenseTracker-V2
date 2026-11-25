import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A package left out of the host script or the workflow would never be
/// analyzed or tested (health check G1-15). Kept from the former
/// workflow_inventory_test; its checks of the workflow's triggers, job
/// count and timeouts were dropped with the workflow-count rule.
void main() {
  final root = p.normalize(p.join(Directory.current.path, '..', '..'));
  final script = File(p.join(root, 'tooling', 'run-host-checks.ps1'))
      .readAsStringSync();
  final registered = RegExp(r"Path = '([^']+)'")
      .allMatches(script)
      .map((m) => m.group(1)!)
      .toSet();

  test('integration workflow covers every registered host package', () {
    final workflow = File(
      p.join(root, '.github', 'workflows', 'integration-validation.yml'),
    ).readAsStringSync();
    final covered = RegExp(
      r"(?:-Package |')((?:apps|packages|modules|infrastructure|tooling)/[a-z_]+"
      r"(?:/[a-z_]+)?)'?",
    ).allMatches(workflow).map((m) => m.group(1)!).toSet();
    expect(covered, registered);
  });

  test('every package on disk is checked by the host script', () {
    final onDisk = <String>{};
    for (final folder in [
      'apps',
      'packages',
      'modules',
      'infrastructure',
      'tooling',
    ]) {
      final location = Directory(p.join(root, folder));
      if (!location.existsSync()) continue;
      for (final entity in location.listSync()) {
        if (entity is! Directory) continue;
        // A folder without a pubspec groups packages one level down, as
        // packages/ledger/<subject> does.
        final packages = File(p.join(entity.path, 'pubspec.yaml')).existsSync()
            ? [entity]
            : entity.listSync().whereType<Directory>().where(
                (d) => File(p.join(d.path, 'pubspec.yaml')).existsSync(),
              );
        for (final package in packages) {
          final relative = p.relative(package.path, from: root);
          onDisk.add(p.posix.joinAll(p.split(relative)));
        }
      }
    }
    expect(registered, onDisk);
  });
}
