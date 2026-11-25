import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:rules/src/cli.dart';
import 'package:rules/src/config.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  final root = findRoot(Directory.current.path);
  final doc =
      loadYaml(File(p.join(root, ownersFile)).readAsStringSync()) as YamlMap;
  final items = (doc['items'] as YamlList).cast<YamlMap>();

  test('owners.yaml lists the 94 single sources with unique kebab ids', () {
    expect(items, hasLength(94));
    final ids = [for (final i in items) i['id'] as String];
    expect(ids.toSet(), hasLength(94));
    final kebab = RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$');
    for (final id in ids) {
      expect(kebab.hasMatch(id), isTrue, reason: id);
    }
  });

  test('every item has the required fields with valid values', () {
    const layers = {'core', 'ledger', 'app', 'design_system', 'data'};
    const statuses = {'owned', 'scattered', 'planned'};
    for (final i in items) {
      final id = i['id'];
      const required = {'id', 'what', 'layer', 'owner', 'target', 'status'};
      expect(i.keys.toSet(), containsAll(required), reason: '$id fields');
      // A scattered item must say how it becomes owned; any may be guarded.
      final extra = i.keys.toSet().difference(required);
      if (i['status'] == 'scattered') {
        expect(extra, contains('plan'), reason: '$id has no plan');
      }
      expect(
        {'plan', 'guard'}.containsAll(extra),
        isTrue,
        reason: '$id has the wrong fields',
      );
      if (i['status'] != 'scattered') {
        expect(extra, isNot(contains('plan')), reason: '$id is no plan');
      }
      expect(layers, contains(i['layer']), reason: '$id layer');
      expect(statuses, contains(i['status']), reason: '$id status');
      expect((i['what'] as String).trim(), isNotEmpty, reason: '$id what');
      expect((i['target'] as String).trim(), isNotEmpty, reason: '$id target');
      expect(i['owner'], isA<YamlList>(), reason: '$id owner');
      if (i['status'] == 'planned') {
        expect(i['owner'], isEmpty, reason: '$id is planned but has owners');
      } else {
        expect(i['owner'], isNotEmpty, reason: '$id has no owner');
      }
    }
  });

  test('a scattered item says how it becomes owned, in one line', () {
    final scattered = [
      for (final i in items)
        if (i['status'] == 'scattered') i,
    ];
    expect(scattered, hasLength(24));
    for (final i in scattered) {
      final plan = i['plan'];
      expect(plan, isA<String>(), reason: '${i['id']} has no plan');
      expect((plan as String).trim(), isNotEmpty, reason: '${i['id']}');
      expect(plan, isNot(contains('\n')), reason: '${i['id']}');
    }
  });

  test('each guard names a rule of tooling/rules or a test file', () {
    final ruleIds = {
      for (final file in Directory(
        p.join(root, 'tooling/rules/lib/src/rules'),
      ).listSync())
        if (file is File)
          for (final m in RegExp(
            r"String get id => '([^']+)'",
          ).allMatches(file.readAsStringSync()))
            m[1]!,
    };
    expect(ruleIds, isNotEmpty);
    var guarded = 0;
    for (final i in items) {
      final guard = i['guard'];
      if (guard == null) continue;
      guarded++;
      expect(guard, isA<YamlList>(), reason: '${i['id']} guard');
      expect(guard as YamlList, isNotEmpty, reason: '${i['id']} guard');
      for (final g in guard.cast<String>()) {
        if (g.contains('/')) {
          expect(g, endsWith('_test.dart'), reason: '${i['id']}: $g');
          expect(
            File(p.join(root, g)).existsSync(),
            isTrue,
            reason: '${i['id']}: $g',
          );
        } else {
          expect(ruleIds, contains(g), reason: '${i['id']}: $g');
        }
      }
    }
    expect(guarded, greaterThanOrEqualTo(11));
  });

  test('every owner path exists in the repository', () {
    final missing = <String>[];
    for (final i in items) {
      for (final path in (i['owner'] as YamlList).cast<String>()) {
        if (FileSystemEntity.typeSync(p.join(root, path)) ==
            FileSystemEntityType.notFound) {
          missing.add('${i['id']}: $path');
        }
      }
    }
    expect(missing, isEmpty);
  });
}
