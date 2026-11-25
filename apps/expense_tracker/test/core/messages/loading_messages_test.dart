import 'package:expense_tracker/src/core/ledger/persistence/ledger_data_source.dart';
import 'package:expense_tracker/src/core/ledger/persistence/quarantine.dart';
import 'package:expense_tracker/src/core/ledger/persistence/upgrade_backup.dart';
import 'package:expense_tracker/src/core/messages/loading_messages.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const rows = [
    QuarantinedRow(
      'entry',
      'e1',
      QuarantineReason.unreadable,
      detail: 'not JSON',
    ),
    QuarantinedRow('budget', 'c1', QuarantineReason.newer, version: 3),
    QuarantinedRow(
      'account',
      'a1',
      QuarantineReason.invalid,
      detail: 'FormatException: Expected a whole number',
    ),
  ];

  test('the notice says how many, and what a later version wrote', () {
    expect(quarantineTitle(3), '有 3 筆資料讀不出來，已先隔離');
    final body = quarantineBody(rows);
    expect(body, contains('其中 1 筆由較新版本寫入'));
    expect(body, contains('不會改寫或刪除'));
    expect(
      quarantineBody([rows[1]]),
      isNot(contains('從備份還原')),
      reason: 'only a later version wrote it: updating the app is the way',
    );
  });

  test('the report lists each row by where it is kept, and why', () {
    expect(
      openingReport(rows: rows, log: '2026-10-04 打開帳本'),
      '記帳本 打開診斷\n'
      '隔離的資料：3 筆\n'
      '紀錄 entry/e1：讀不出來（not JSON）\n'
      '預算 budget/c1：由較新版本寫入（第 3 版）\n'
      '帳戶 account/a1：內容不完整'
      '（FormatException: Expected a whole number）\n'
      '\n'
      '診斷紀錄\n'
      '2026-10-04 打開帳本',
    );
    expect(
      openingReport(failure: 'SqliteException: disk I/O error'),
      '記帳本 打開診斷\n無法打開：SqliteException: disk I/O error',
    );
  });

  test('what is told of a row never quotes it', () {
    final detail = quarantineDetail(
      const FormatException('amount: expected words', '{"note":"祕密"}', 3),
    );
    expect(detail, 'FormatException: amount: expected words');
    expect(quarantineDetail(StateError('x')), 'StateError');
  });

  test('the held upgrade says its cause as one sentence, closed once '
      '(review 31, 7)', () {
    // An error the person can act on: its sentence, then this page's.
    expect(
      upgradeHeldBody(
        UpgradeBackupProblem.other,
        const DataSourceException('x'),
      ),
      '無法先把帳本備份起來：帳本無法寫入，請重新打開 App 再試。'
      '帳本沒有被改動，也還沒有升級到這個版本。',
    );
    expect(
      upgradeHeldBody(UpgradeBackupProblem.other, StateError('x')),
      '無法先把帳本備份起來，可在診斷匯出詳細資料。'
      '帳本沒有被改動，也還沒有升級到這個版本。',
    );
    expect(
      upgradeHeldBody(UpgradeBackupProblem.noSpace, StateError('x')),
      '手機空間不足，無法先把帳本備份起來。帳本沒有被改動，也還沒有升級到這個版本。',
    );
  });
}
