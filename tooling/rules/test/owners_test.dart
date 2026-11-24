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

  test('owners.yaml lists the 72 single sources with unique kebab ids', () {
    expect(items, hasLength(72));
    final ids = [for (final i in items) i['id'] as String];
    expect(ids.toSet(), hasLength(72));
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
      expect(i.keys.toSet(), {
        'id',
        'what',
        'layer',
        'owner',
        'target',
        'status',
      }, reason: '$id has the wrong fields');
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
