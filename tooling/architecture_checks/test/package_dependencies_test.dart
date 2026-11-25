import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// What each package of the core may list among its dependencies (path
/// dependencies, by folder): the direction every arrow of
/// docs/architecture.md 模組 points. A package not named here fails the
/// test until it is: its place is a decision, not an accident. The
/// ledger's subject packages are in an order (trade_costs, entries,
/// postings): each may list only those before it.
const corePackages = {
  'packages/core': <String>{},
  'packages/domain': {'packages/core'},
  'packages/kernel': {'packages/core'},
  'packages/shell': {'packages/core', 'packages/kernel'},
  'packages/ledger/trade_costs': {'packages/core'},
  'packages/ledger/entries': {'packages/core', 'packages/ledger/trade_costs'},
  'packages/ledger/postings': {
    'packages/core',
    'packages/domain',
    'packages/kernel',
    'packages/ledger/entries',
    'packages/ledger/trade_costs',
  },
  'infrastructure/storage': {'packages/kernel'},
  'infrastructure/vault': {'infrastructure/storage'},
  'infrastructure/market': {'packages/core'},
};

/// What a module may list: the core and the shell, never another module
/// (nor the data packages or the app).
bool moduleMayList(String dependency) =>
    {
      'packages/core',
      'packages/kernel',
      'packages/shell',
    }.contains(dependency) ||
    dependency.startsWith('packages/ledger/');

/// The app: the one file that names a module's feature.
const compositionRoot = 'lib/src/app/modules.dart';

final root = p.normalize(p.join(Directory.current.path, '..', '..'));

String _rel(String path) => p.relative(path, from: root).replaceAll(r'\', '/');

/// Every package folder (one with a pubspec.yaml) under [dirs].
List<String> packagesUnder(List<String> dirs) => [
  for (final dir in dirs)
    if (Directory(p.join(root, dir)).existsSync())
      for (final f in Directory(p.join(root, dir)).listSync(recursive: true))
        if (f is File &&
            p.basename(f.path) == 'pubspec.yaml' &&
            !f.path.contains('${p.separator}.dart_tool${p.separator}') &&
            !f.path.contains('${p.separator}build${p.separator}'))
          _rel(p.dirname(f.path)),
]..sort();

/// The package's name and its path dependencies (normal and dev), as
/// folders from the repository's root.
(String, Set<String>) pubspecOf(String package) {
  final yaml = loadYaml(
    File(p.join(root, package, 'pubspec.yaml')).readAsStringSync(),
  ) as YamlMap;
  final deps = <String>{};
  for (final section in ['dependencies', 'dev_dependencies']) {
    final map = yaml[section];
    if (map is! YamlMap) continue;
    for (final value in map.values) {
      if (value is YamlMap && value['path'] is String) {
        deps.add(
          _rel(p.normalize(p.join(root, package, value['path'] as String))),
        );
      }
    }
  }
  return (yaml['name'] as String, deps);
}

void main() {
  final modules = packagesUnder(['modules']);

  test('every core package lists only what it may', () {
    final offenders = <String>[];
    final unknown = <String>[];
    for (final package in packagesUnder(['packages', 'infrastructure'])) {
      final allowed = corePackages[package];
      if (allowed == null) {
        unknown.add(package);
        continue;
      }
      for (final dep in pubspecOf(package).$2) {
        if (!allowed.contains(dep)) offenders.add('$package -> $dep');
      }
    }
    expect(unknown, isEmpty, reason: 'declare its place in corePackages');
    expect(offenders, isEmpty);
    // Every declared package is there: the table does not go stale.
    expect(
      corePackages.keys.where(
        (k) => !File(p.join(root, k, 'pubspec.yaml')).existsSync(),
      ),
      isEmpty,
    );
  });

  test('a module lists only the core and the shell, never another module', () {
    expect(modules, contains('modules/loans'));
    final offenders = <String>[
      for (final module in modules)
        for (final dep in pubspecOf(module).$2)
          if (!moduleMayList(dep)) '$module -> $dep',
    ];
    expect(offenders, isEmpty);
  });

  test('a module is lib/calc, lib/feature and test', () {
    final missing = <String>[
      for (final module in modules)
        for (final dir in ['lib/calc', 'lib/feature', 'test'])
          if (!Directory(p.join(root, module, dir)).existsSync())
            '$module/$dir',
    ];
    expect(missing, isEmpty);
  });

  test("the app reaches a module's feature only at its composition root", () {
    final names = [for (final m in modules) pubspecOf(m).$1];
    final app = p.join(root, 'apps', 'expense_tracker');
    final offenders = <String>[];
    var rooted = 0;
    for (final f in Directory(p.join(app, 'lib')).listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final path = p.relative(f.path, from: app).replaceAll(r'\', '/');
      final text = f.readAsStringSync();
      for (final name in names) {
        if (!text.contains("'package:$name/feature/")) continue;
        if (path == compositionRoot) {
          rooted++;
        } else {
          offenders.add('$path imports $name/feature');
        }
      }
    }
    expect(offenders, isEmpty);
    expect(rooted, names.length, reason: 'each module installed at the root');
  });
}
