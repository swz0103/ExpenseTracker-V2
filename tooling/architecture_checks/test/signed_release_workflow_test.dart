import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  test('signed Android release is manual, protected, and fail closed', () {
    final root = p.normalize(p.join(Directory.current.path, '..', '..'));
    final source = File(
      p.join(root, '.github', 'workflows', 'signed-android-release.yml'),
    ).readAsStringSync();
    final yaml = loadYaml(source) as YamlMap;
    final triggers = yaml['on'] as YamlMap;
    final dispatch = triggers['workflow_dispatch'] as YamlMap;
    final inputs = dispatch['inputs'] as YamlMap;
    final confirmation = inputs['confirm_signed_release'] as YamlMap;
    expect(confirmation['required'], isTrue);
    expect(confirmation['type'], 'boolean');

    final jobs = yaml['jobs'] as YamlMap;
    expect(jobs, hasLength(1));
    final job = jobs['build-and-release'] as YamlMap;
    expect(job['if'], contains("github.ref_name == 'main'"));
    expect(job['environment'], 'android-production');
    expect(job['runs-on'], 'ubuntu-latest');
    expect(job['timeout-minutes'], lessThanOrEqualTo(55));

    final steps = job['steps'] as YamlList;
    final externalActions = steps
        .whereType<YamlMap>()
        .map((step) => step['uses'])
        .whereType<String>();
    for (final action in externalActions) {
      expect(action, matches(RegExp(r'^[^@]+@[0-9a-f]{40}$')));
    }

    expect(source, contains(r'${{ vars.ANDROID_RELEASE_APPLICATION_ID }}'));
    expect(source, contains(r'${{ vars.ANDROID_RELEASE_CERT_SHA256 }}'));
    expect(source, contains(r'${{ secrets.ANDROID_RELEASE_KEYSTORE_BASE64 }}'));
    expect(source, contains('ORG_GRADLE_PROJECT_v2EnableReleaseSigning'));
    expect(source, contains('certificate SHA-256 does not match'));
    expect(source, contains('apksigner" verify --verbose --print-certs'));
    expect(source, contains('keytool" -printcert -jarfile'));
    expect(source, contains('actual_aab_cert_sha256'));
    expect(source, contains('if: always()'));
    expect(source, contains(r'${{ runner.temp }}/expense-v2-release.jks'));
    expect(source, contains(r'"$RUNNER_TEMP"/*) rm -f'));
  });
}
