/// D84: what Drive answered stays in the diagnostics; the person reads a
/// sentence.
library;

import 'package:expense_tracker/src/features/backup/model/drive_backup.dart';
import 'package:expense_tracker/src/features/backup/model/drive_note.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('each Drive problem is said in words, a refusal without its answer', () {
    expect(
      driveNote(const DriveException(DriveProblem.refused, '403 Rate limit')),
      'Google 雲端硬碟沒有接受這次的要求，可在診斷匯出詳細資料',
    );
    expect(
      driveNote(const DriveException(DriveProblem.notAllowed)),
      '沒有取得 Google 雲端硬碟的權限',
    );
    expect(
      driveNote(const DriveException(DriveProblem.offline, 'SocketException')),
      '連不上 Google，請稍後再試',
    );
    expect(
      driveNote(const DriveException(DriveProblem.noAnswer)),
      'Google 沒有回應，請再試一次',
    );
  });
}
