import 'package:expense_tracker/src/core/messages/key_messages.dart';
import 'package:flutter_test/flutter_test.dart';

/// D15: what is said of the backups sealed with keys a reset replaced.
void main() {
  test('each place with how many and their dates, and what is not listed', () {
    expect(
      KeyWords.oldBackupsBody(
        drive: ['2026/11/20', '2026/11/13'],
        phone: ['2026/11/22'],
        driveUnreached: false,
      ),
      '這些備份是重設前用舊金鑰做的，用舊的密碼或救援碼仍打得開。\n\n'
      'Google 雲端硬碟：2 份（2026/11/20、2026/11/13），移到雲端硬碟的垃圾桶，30 天後自動刪除\n\n'
      '這支手機：1 份（2026/11/22），會直接刪除\n\n'
      '資料夾、匯出的檔案與 Google 系統備份裡的舊備份不在此列，請自行處理。',
    );
    expect(
      KeyWords.oldBackupsBody(drive: [], phone: [], driveUnreached: true),
      contains('連不上 Google 雲端硬碟'),
    );
    expect(KeyWords.oldBackupsGone(3), '已刪除 3 份舊金鑰的備份');
  });
}
