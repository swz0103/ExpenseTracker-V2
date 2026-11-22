import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Packages that exist on disk but are not yet registered in
/// tooling/run-host-checks.ps1 / the integration workflow. Empty once the
/// CI owner registers tooling/rules; delete this set then.
const pendingRegistration = {'tooling/rules'};

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
      r"(?:-Package |')((?:apps|packages|infrastructure|tooling)/[a-z_]+)'?",
    ).allMatches(workflow).map((m) => m.group(1)!).toSet();
    expect(
      covered.union(pendingRegistration),
      registered.union(pendingRegistration),
    );
  });

  test('every package on disk is checked by the host script', () {
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
    expect(registered.union(pendingRegistration), onDisk);
  });
}
