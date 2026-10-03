import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  test('preview release is gated, stably signed and least-privilege', () {
    final root = p.normalize(p.join(Directory.current.path, '..', '..'));
    final source = File(
      p.join(root, '.github', 'workflows', 'preview-release.yml'),
    ).readAsStringSync();
    final yaml = loadYaml(source) as YamlMap;
    expect((yaml['permissions'] as YamlMap)['contents'], 'read');

    final jobs = yaml['jobs'] as YamlMap;
    final validate = jobs['validate'] as YamlMap;
    expect(validate['if'], contains("github.ref_name == 'main'"));
    expect(validate['uses'], './.github/workflows/integration-validation.yml');
    final build = jobs['build'] as YamlMap;
    expect(build['needs'], 'validate');
    expect(build['permissions'], isNull);
    final publish = jobs['publish'] as YamlMap;
    expect(publish['needs'], 'build');
    expect((publish['permissions'] as YamlMap)['contents'], 'write');

    for (final job in [build, publish]) {
      for (final step in (job['steps'] as YamlList).whereType<YamlMap>()) {
        final action = step['uses'];
        if (action is String) {
          expect(action, matches(RegExp(r'^[^@]+@[0-9a-f]{40}$')));
        }
      }
    }
    expect(source, contains('persist-credentials: false'));
    expect(source, contains(r'${{ secrets.ANDROID_PREVIEW_KEYSTORE_BASE64 }}'));
    expect(source, contains('refusing an unstable signature'));
    expect(source, contains('V2_PREVIEW_STORE_FILE'));
  });
}
