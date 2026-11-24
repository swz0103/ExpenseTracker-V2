/// D84: a step running by itself that fails is told, once a run.
library;

import 'package:expense_tracker/src/app/quiet_failures.dart';
import 'package:expense_tracker/src/core/messages/problem_messages.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('each kind is said once a run, in a sentence with where the '
      'details are', () {
    final said = <String>[];
    final quiet = QuietFailures(said.add);
    quiet
      ..failed(QuietStep.backgroundBackup)
      ..failed(QuietStep.backgroundBackup)
      ..failed(QuietStep.calendarSync);
    expect(said, ['背景備份沒有完成，可在診斷匯出詳細資料', '提醒沒有同步到日曆，可在診斷匯出詳細資料']);
  });

  test('every quiet step has its words', () {
    expect(
      {for (final s in QuietStep.values) s.note},
      {
        '到期的定期交易沒有自動入帳，可在診斷匯出詳細資料',
        '背景備份沒有完成，可在診斷匯出詳細資料',
        '收盤價與匯率沒有更新，可在診斷匯出詳細資料',
        '提醒沒有同步到日曆，可在診斷匯出詳細資料',
      },
    );
  });
}
