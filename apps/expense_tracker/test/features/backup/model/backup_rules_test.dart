import 'dart:convert';
import 'dart:io';

import 'package:expense_tracker/src/core/platform/preferences.dart';
import 'package:expense_tracker/src/features/backup/model/backup_rules.dart';
import 'package:flutter_test/flutter_test.dart';

/// The backups' rules have one owner, and the background job
/// (BackupWorker.kt) follows the ones it is handed (review 32, 2.1).
void main() {
  const kotlin = 'android/app/src/main/kotlin/io/github/swz0103/expensetracker';

  test('five stay; the phone daily or weekly, Drive daily, the app weekly', () {
    expect(BackupRules.keep, 5);
    expect(BackupRules.phoneEvery(daily: true), const Duration(days: 1));
    expect(BackupRules.phoneEvery(daily: false), const Duration(days: 7));
    expect(BackupRules.drive, const Duration(days: 1));
    expect(BackupRules.own, const Duration(days: 7));
    expect(BackupRules.driveFolder, '記帳本備份');
  });

  test('a ledger\'s backups in the phone\'s folder are named by its mark '
      'and the time, so they sort by time', () {
    expect(BackupRules.markOf('ledger-one'), 'ledger');
    expect(BackupRules.markOf('a1-b2'), 'a1b2');
    expect(
      BackupRules.phoneName('abc123', DateTime(2026, 10, 28, 11, 4)),
      '記帳本-abc123-20261028-1104.etbk',
    );
    expect(BackupRules.phonePrefix('abc123'), '記帳本-abc123-');
  });

  test('the job is handed every rule, in the fields it reads', () {
    final handed = BackupRules.handover(
      'abc123',
      DateTime(2026, 10, 28, 11, 4),
    );
    expect(handed, {
      'keep': 5,
      'daily': 86400000, // 24 × 60 × 60 × 1000
      'weekly': 604800000, // 7 × 86,400,000
      'drive': 86400000,
      'phoneName': '記帳本-abc123-20261028-1104.etbk',
      'phonePrefix': '記帳本-abc123-',
      'suffix': '.etbk',
      'driveFolder': '記帳本備份',
      'folderDenied': '沒有這個資料夾的存取權，請重新選擇',
    });
    // BackupWorker.kt reads each into BackupPlan.Handed, and reads no other.
    final worker = File('$kotlin/BackupWorker.kt').readAsStringSync();
    final start = worker.indexOf('BackupPlan.Handed(');
    final body = worker.substring(
      start,
      worker.indexOf('\n            )', start),
    );
    final read = {
      for (final m in RegExp(r'it\.get\w+\("(\w+)"\)').allMatches(body)) m[1]!,
    };
    expect(read, handed.keys.toSet());
    final plan = File('$kotlin/BackupPlan.kt').readAsStringSync();
    for (final field in handed.keys) {
      expect(plan, contains('val $field: '), reason: field);
    }
  });

  test('the times the job reads from the settings are written as it parses '
      'them (BackupPlan.millisOf: yyyy-MM-ddTHH:mm:ss, a fraction, UTC)', () {
    final folder = Directory.systemTemp.createTempSync('rules-');
    addTearDown(() => folder.deleteSync(recursive: true));
    final file = File('${folder.path}/preferences.json');
    Preferences(file: file)
      ..phoneBackup(DateTime.utc(2026, 10, 28, 3, 4, 5, 123), 1)
      ..update(driveLinked: true)
      ..driveBackup(DateTime.utc(2026, 10, 28, 3, 4, 5, 123), 1);
    final json = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    expect(json['phoneBackedUp'], '2026-10-28T03:04:05.123Z');
    expect(json['driveBackedUp'], '2026-10-28T03:04:05.123Z');
    expect(
      File('$kotlin/BackupPlan.kt').readAsStringSync(),
      contains('SimpleDateFormat("yyyy-MM-dd\'T\'HH:mm:ss", Locale.ROOT)'),
    );
  });
}
