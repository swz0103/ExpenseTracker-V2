import 'dart:io';

import 'package:expense_tracker/src/core/platform/app_files.dart';
import 'package:flutter_test/flutter_test.dart';

/// The app's file and folder names have one owner (`AppFiles`); the
/// Android side needs some before the app runs and keeps them in
/// `AppFiles.kt`, and Android's own backup and file sharing name folders
/// in res/xml. A name changed on one side only would leave a file behind,
/// plaintext among them, with nothing failing (review 32, 2.2), so this
/// holds every copy to the owner.
void main() {
  const android = 'android/app/src';

  test('the names are the ones the files on phones already have', () {
    // Literal: a change here strands every file written under the old name.
    expect(AppFiles.all, {
      'PREFERENCES': 'preferences.json',
      'WIDGET': 'widget.json',
      'RECEIPTS': 'receipts',
      'BACKUPS': 'backups',
      'EXPORTS': 'exports',
      'CLOUD': 'cloud',
      'CLOUD_COPY': '記帳本.etbk',
      'OUTBOX': 'outbox',
      'OUTBOX_READY': 'ready.json',
      'OUTBOX_DELIVERED': 'delivered.json',
      'RESTORE_COPY': 'restore.etbk',
      'UPDATES': 'updates',
      'CAMERA': 'camera',
      'CAMERA_PHOTO': 'receipt.jpg',
      'RECEIPT_READY': 'receipt-ready.jpg',
      'RECEIPT_LEFTOVER': 'receipt-leftover.jpg',
    });
  });

  test('each name AppFiles.kt has is the app\'s', () {
    final kotlin = File(
      '$android/main/kotlin/io/github/swz0103/expensetracker/AppFiles.kt',
    ).readAsStringSync();
    final names = {
      for (final m in RegExp(r'const val (\w+) = "([^"]*)"').allMatches(kotlin))
        m[1]!: m[2]!,
    };
    // The names the Android side reads or writes itself.
    expect(names.keys.toSet(), {
      'PREFERENCES',
      'WIDGET',
      'OUTBOX',
      'OUTBOX_READY',
      'OUTBOX_DELIVERED',
      'RESTORE_COPY',
      'CAMERA',
      'CAMERA_PHOTO',
      'RECEIPT_READY',
      'RECEIPT_LEFTOVER',
    });
    for (final MapEntry(:key, :value) in names.entries) {
      expect(value, AppFiles.all[key], reason: key);
    }
  });

  test('Android\'s backup takes the cloud folder, and the camera and the '
      'installer share theirs', () {
    String read(String path) => File('$android/$path').readAsStringSync();
    for (final rules in [
      'main/res/xml/backup_rules.xml',
      'main/res/xml/data_extraction_rules.xml',
    ]) {
      expect(read(rules), contains('path="${AppFiles.cloud}/"'), reason: rules);
    }
    expect(
      read('main/res/xml/file_paths.xml'),
      contains('path="${AppFiles.camera}/"'),
    );
    final sideload = read('sideload/res/xml/file_paths.xml');
    expect(sideload, contains('path="${AppFiles.camera}/"'));
    expect(sideload, contains('path="${AppFiles.updates}/"'));
  });
}
