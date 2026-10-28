import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Android's backup rules (res/xml) keep what belongs to this phone alone,
/// and what would not fit, out of the cloud backup and the move to a new
/// phone. The three lists must agree with each other and with the files
/// the app writes: a folder renamed in the code but not in the rules
/// would start travelling where it should not.
void main() {
  const xml = 'android/app/src/main/res/xml';

  /// The `<exclude domain="file" path=…>` of [section] (all when null).
  Set<String> excluded(String file, {String? section}) {
    var text = File('$xml/$file').readAsStringSync();
    if (section != null) {
      final start = text.indexOf('<$section>');
      final end = text.indexOf('</$section>');
      expect(start, isNonNegative, reason: '$file has no <$section>');
      text = text.substring(start, end);
    }
    return {
      for (final m in RegExp(
        r'<exclude\s+domain="file"\s+path="([^"]+)"\s*/>',
      ).allMatches(text))
        m[1]!,
    };
  }

  // This phone's own: its fingerprint enrolment, the files waiting to be
  // handed over, the calendar chosen, the error log, the backup waiting
  // for the background job.
  const ownPhone = {
    'device-id',
    'no-fingerprint',
    'exports',
    'calendar',
    'diagnostics.log',
    'outbox',
  };
  // Too large for the 25 MB cloud allowance; they still move with the
  // phone-to-phone transfer.
  const tooLarge = {'receipts', 'before-restore'};

  test('the cloud backup keeps out this phone\'s files and the large ones', () {
    final cloud = excluded(
      'data_extraction_rules.xml',
      section: 'cloud-backup',
    );
    expect(cloud, {...ownPhone, ...tooLarge});
    // Android 11 and earlier read backup_rules.xml: the same list.
    expect(excluded('backup_rules.xml'), cloud);
  });

  test('the move to a new phone keeps out only this phone\'s files', () {
    expect(
      excluded('data_extraction_rules.xml', section: 'device-transfer'),
      ownPhone,
    );
  });

  test('every path kept out is one the app writes', () {
    final sources = [
      for (final f in Directory('lib').listSync(recursive: true))
        if (f is File && f.path.endsWith('.dart')) f.readAsStringSync(),
    ].join('\n');
    for (final path in {...ownPhone, ...tooLarge}) {
      expect(
        sources.contains("/$path'"),
        isTrue,
        reason: 'no file or folder "$path" in lib/: renamed?',
      );
    }
  });
}
