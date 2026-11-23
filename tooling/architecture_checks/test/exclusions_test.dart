import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// Code left out of the analysis is code nothing looks at, and it breaks
/// without anyone knowing: the emulator bench did, for weeks. So every
/// path an analysis_options.yaml leaves out is listed here with the check
/// that still covers it on every pull request, or why none is needed.
void main() {
  final root = p.normalize(p.join(Directory.current.path, '..', '..'));

  /// Excluded path (from the repository root) → (workflow, words of the
  /// step that covers it), or null with the reason in a comment.
  const guards = <String, (String, String)?>{
    // What the build writes; never written by hand.
    'apps/expense_tracker/build/**': null,
    'apps/expense_tracker/web/**': ('web-preview.yml', 'flutter build web'),
    'apps/expense_tracker/integration_test/**': (
      'integration-validation.yml',
      'flutter analyze integration_test test_driver',
    ),
    'apps/expense_tracker/test_driver/**': (
      'integration-validation.yml',
      'flutter analyze integration_test test_driver',
    ),
    'apps/expense_tracker/android/**': (
      'android.yml',
      ':app:testSideloadDebugUnitTest',
    ),
  };

  test('every path left out of the analysis is still checked', () {
    final excluded = <String>{};
    for (final f in Directory(root).listSync(recursive: true)) {
      if (f is! File || p.basename(f.path) != 'analysis_options.yaml') continue;
      if (f.path.contains('${p.separator}.')) continue;
      if (f.path.contains('${p.separator}build${p.separator}')) continue;
      final yaml = loadYaml(f.readAsStringSync());
      final analyzer = yaml is YamlMap ? yaml['analyzer'] : null;
      final list = analyzer is YamlMap ? analyzer['exclude'] : null;
      if (list is! YamlList) continue;
      final dir = p.relative(p.dirname(f.path), from: root);
      for (final path in list) {
        excluded.add(p.posix.join(dir.replaceAll(r'\', '/'), '$path'));
      }
    }
    expect(
      excluded,
      guards.keys.toSet(),
      reason: 'an excluded path needs a check that covers it, listed here',
    );
  });

  test('each check named for an excluded path runs on pull requests', () {
    for (final MapEntry(key: path, value: guard) in guards.entries) {
      if (guard == null) continue;
      final (workflow, words) = guard;
      final text = File(p.join(root, '.github', 'workflows', workflow))
          .readAsStringSync();
      expect(text, contains(words), reason: '$path: $workflow lost its check');
      final on = (loadYaml(text) as YamlMap)['on'] as YamlMap;
      expect(
        on.containsKey('pull_request'),
        isTrue,
        reason: '$path: $workflow does not run on pull requests',
      );
    }
  });
}
