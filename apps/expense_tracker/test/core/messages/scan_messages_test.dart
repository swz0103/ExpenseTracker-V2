import 'package:expense_tracker/src/core/messages/scan_messages.dart';
import 'package:expense_tracker/src/core/platform/scan.dart';
import 'package:flutter_test/flutter_test.dart';

/// F66: each way the scanner can fail says what to do next.
void main() {
  test('each failure has its words', () {
    expect(
      {
        for (final failure in ScanFailure.values)
          failure: ScanMessages.failure(failure),
      },
      {
        ScanFailure.unavailable:
            '無法下載掃描器。請確認手機有網路、還有儲存空間，並且 Google Play 服務已開啟並更新，'
            '再按一次「掃發票」；也可以直接手動輸入這張發票。',
        ScanFailure.busy: '掃描器已經開著',
        ScanFailure.failed: '沒有掃到。請再按一次「掃發票」，或直接手動輸入這張發票。',
      },
    );
    expect(ScanMessages.preparing, '第一次使用要先下載掃描器，請稍候…');
    expect(ScanMessages.step, '掃發票');
  });
}
