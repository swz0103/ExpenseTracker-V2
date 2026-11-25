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

  test('PRIV-1: the jobs read the settings the app hands them '
      '(background.json), not the settings file, and each key they read is '
      'one handed over', () {
    final handed = Preferences.backgroundPlan(
      updateChecks: true,
      drive: (photosOnWifi: true, at: DateTime.utc(2026, 10, 28), revision: 1),
      phone: (
        folder: 'sealed',
        id: 'f1',
        daily: false,
        at: DateTime.utc(2026, 10, 28),
        revision: 1,
      ),
    );
    final drive = handed['drive']! as Map<String, Object?>;
    final phone = handed['phone']! as Map<String, Object?>;
    expect(handed.keys, ['v', 'updateChecks', 'drive', 'phone']);
    expect(drive.keys, ['photosOnWifi', 'at', 'revision']);
    expect(phone.keys, ['folder', 'id', 'daily', 'at', 'revision']);
    // 2026-10-28T00:00:00Z is 1,793,145,600,000 ms after 1970: the job
    // reads milliseconds, and parses no date.
    expect(drive['at'], 1793145600000);

    final worker = File('$kotlin/BackupWorker.kt').readAsStringSync();
    expect(worker, isNot(contains('PREFERENCES')));
    for (final read in [
      'AppFiles.BACKGROUND',
      'optJSONObject("phone")',
      'optJSONObject("drive")',
      'phone.getString("id")',
      'phone.getString("folder")',
      'phone.optBoolean("daily")',
      'drive.optBoolean("photosOnWifi", true)',
      'handed.isNull("at")',
      'handed.optLong("at")',
      'handed.isNull("revision")',
      'handed.optInt("revision")',
      '.isNull("drive")',
    ]) {
      expect(worker, contains(read), reason: read);
    }
    final update = File(
      'android/app/src/sideload/kotlin/io/github/swz0103/expensetracker/'
      'UpdateWorker.kt',
    ).readAsStringSync();
    expect(update, contains('AppFiles.BACKGROUND'));
    expect(update, contains('optBoolean("updateChecks", true)'));
    // The folder opens with what the app sealed it for.
    expect(
      File('$kotlin/QuickSeal.kt').readAsStringSync(),
      contains('const val FOLDER_CONTEXT = "${Preferences.folderContext}"'),
    );
  });
}
