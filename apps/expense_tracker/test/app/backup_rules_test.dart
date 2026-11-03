import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Android's own backup takes one thing of the app: the encrypted copy of
/// the ledger in files/cloud/ (Startup.cloudCopy), to the person's Google
/// account and to a new phone. Not the ledger itself, its key or the
/// settings: brought back, the welcome offers the copy and replaces
/// nothing unasked. Android 11 and earlier read backup_rules.xml,
/// Android 12 and later data_extraction_rules.xml.
void main() {
  const android = 'android/app/src/main';
  const onlyTheCopy = {'file:cloud/'};

  String read(String name) => File('$android/res/xml/$name').readAsStringSync();

  /// The `<include domain=… path=…>` of [part] as `domain:path`; [part]
  /// excludes nothing, so what is not included stays on the phone.
  Set<String> included(String part) {
    expect(part.contains('<exclude'), isFalse, reason: 'excludes');
    return {
      for (final m in RegExp(
        r'<include\s+domain="([^"]+)"\s+path="([^"]+)"\s*/>',
      ).allMatches(part))
        '${m[1]}:${m[2]}',
    };
  }

  String section(String text, String name) {
    final start = text.indexOf('<$name>');
    final end = text.indexOf('</$name>');
    expect(start, isNonNegative, reason: 'no <$name>');
    return text.substring(start, end);
  }

  test('the manifest turns the backup on with the rules', () {
    final manifest = File('$android/AndroidManifest.xml').readAsStringSync();
    expect(manifest, contains('android:allowBackup="true"'));
    expect(manifest, contains('android:fullBackupContent="@xml/backup_rules"'));
    expect(
      manifest,
      contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
    );
  });

  test('only the copy goes to the cloud backup', () {
    final rules = read('data_extraction_rules.xml');
    expect(included(section(rules, 'cloud-backup')), onlyTheCopy);
  });

  test('only the copy moves to a new phone', () {
    final rules = read('data_extraction_rules.xml');
    expect(included(section(rules, 'device-transfer')), onlyTheCopy);
  });

  test('Android 11 and earlier take only the copy too', () {
    expect(included(read('backup_rules.xml')), onlyTheCopy);
  });

  test('the copy is where the app writes it', () {
    final startup = File('lib/src/features/lock/model/startup.dart')
        .readAsStringSync();
    expect(startup, contains(r"'${directory.path}/cloud/記帳本.etbk'"));
  });
}
