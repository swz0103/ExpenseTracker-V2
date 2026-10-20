import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The business rules run anywhere: no files, network, database or UI.
const platformFree = ['packages/core', 'packages/domain'];

/// The only SDK libraries the business packages may use.
const allowedSdk = {
  'dart:async',
  'dart:collection',
  'dart:convert',
  'dart:core',
  'dart:math',
  'dart:typed_data',
};

/// Packages the business rules must never reach for.
const forbiddenPackages = {'flutter', 'storage', 'vault', 'market', 'sqlite3'};

final _directive = RegExp(r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''');

void main() {
  test('core and domain import no platform library', () {
    final root = p.normalize(p.join(Directory.current.path, '..', '..'));
    final offenders = <String>[];
    var checked = 0;
    for (final package in platformFree) {
      final lib = Directory(p.join(root, package, 'lib'));
      for (final file in lib.listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.dart')) continue;
        checked++;
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final uri = _directive.firstMatch(lines[i])?.group(1);
          if (uri == null) continue;
          final where = '${p.relative(file.path, from: root)}:${i + 1} $uri';
          if (uri.startsWith('dart:') && !allowedSdk.contains(uri)) {
            offenders.add(where);
          }
          if (uri.startsWith('package:')) {
            final name = uri.substring('package:'.length).split('/').first;
            if (forbiddenPackages.contains(name)) offenders.add(where);
          }
        }
      }
    }
    expect(checked, greaterThan(20));
    expect(offenders, isEmpty);
  });
}
