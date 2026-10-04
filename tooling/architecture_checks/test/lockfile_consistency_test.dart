import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// Each package keeps its own lockfile, so a shared dependency could drift
/// to different versions without anyone noticing (code audit M-03). Every
/// Dart package must lock the same version of each hosted package. The
/// Flutter app is left out: the Flutter SDK pins its own versions.
void main() {
  test('every lockfile pins the same version of a shared package', () {
    final root = p.normalize(p.join(Directory.current.path, '..', '..'));
    final versions = <String, Map<String, List<String>>>{};
    var checked = 0;
    for (final top in ['packages', 'infrastructure', 'tooling']) {
      for (final dir in Directory(p.join(root, top)).listSync()) {
        final lock = File(p.join(dir.path, 'pubspec.lock'));
        if (dir is! Directory || !lock.existsSync()) continue;
        checked++;
        final name = p.relative(dir.path, from: root);
        final yaml = loadYaml(lock.readAsStringSync()) as YamlMap;
        final packages = yaml['packages'] as YamlMap;
        for (final entry in packages.entries) {
          final info = entry.value as YamlMap;
          if (info['source'] != 'hosted') continue;
          final package = entry.key as String;
          final version = info['version'] as String;
          final byVersion = versions[package] ??= {};
          (byVersion[version] ??= []).add(name);
        }
      }
    }
    expect(checked, greaterThan(20));
    final drifted = {
      for (final MapEntry(key: package, value: byVersion) in versions.entries)
        if (byVersion.length > 1) package: byVersion,
    };
    expect(drifted, isEmpty, reason: 'Align these versions: $drifted');
  });
}
