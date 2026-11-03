import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Nothing of the app goes with Android's own backup: reinstalled or on a
/// new phone it starts on its welcome, and a ledger comes back only
/// through 還原備份. Android 11 and earlier, and the cloud backup, follow
/// allowBackup; Android 12 and later still move an app's files to a new
/// phone unless the rules keep every place out.
void main() {
  const android = 'android/app/src/main';
  const places = {'root', 'file', 'database', 'sharedpref', 'external'};

  /// The `<exclude domain=… path=…>` of [section] as `domain:path`.
  Set<String> excluded(String section) {
    final text = File(
      '$android/res/xml/data_extraction_rules.xml',
    ).readAsStringSync();
    final start = text.indexOf('<$section>');
    final end = text.indexOf('</$section>');
    expect(start, isNonNegative, reason: 'no <$section>');
    final part = text.substring(start, end);
    expect(part.contains('<include'), isFalse, reason: '$section includes');
    return {
      for (final m in RegExp(
        r'<exclude\s+domain="([^"]+)"\s+path="([^"]+)"\s*/>',
      ).allMatches(part))
        '${m[1]}:${m[2]}',
    };
  }

  final everything = {for (final p in places) '$p:.'};

  test('Android backs up nothing of the app', () {
    final manifest = File('$android/AndroidManifest.xml').readAsStringSync();
    expect(manifest, contains('android:allowBackup="false"'));
    expect(manifest, contains('@xml/data_extraction_rules'));
    expect(manifest.contains('fullBackupContent'), isFalse);
  });

  test('nothing goes to the cloud backup', () {
    expect(excluded('cloud-backup'), everything);
  });

  test('nothing moves to a new phone', () {
    expect(excluded('device-transfer'), everything);
  });
}
