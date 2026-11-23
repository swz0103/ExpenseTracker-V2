import 'package:expense_tracker/src/core/messages/update_messages.dart';
import 'package:expense_tracker/src/core/platform/update_status.dart';
import 'package:flutter_test/flutter_test.dart';

/// F102: however the build stands against the newest, 關於 has words for
/// it, and every failure says why.
void main() {
  test('each standing has its words', () {
    String? say(UpdateStatus status) =>
        UpdateMessages.status(status, version: '2.0.3');
    expect(say(const UpdateNotLooked()), '點這裡檢查更新');
    expect(say(const UpdateChecking()), '檢查中…');
    expect(say(const UpdateCurrent()), '已是最新版本（2.0.3）');
    expect(say(const UpdateAvailable('2.1.0')), '有新版 2.1.0');
    // 0.624 of it is here: 62%.
    expect(say(const UpdateDownloading(0.624)), '下載中 62%');
    expect(say(const UpdateHandBuilt()), '自行建置的版本');
    expect(say(const UpdateFailed(UpdateFailure.offline)), '連不上 GitHub，請稍後再試');
    // The play build is updated by Google Play: nothing to say here.
    expect(say(const UpdateNotOffered()), isNull);
  });

  test('a build without a version number says it is the newest plainly', () {
    expect(UpdateMessages.status(const UpdateCurrent(), version: ''), '已是最新版本');
  });

  test('each failure says why', () {
    expect(
      {
        for (final failure in UpdateFailure.values)
          failure: UpdateMessages.failure(failure),
      },
      {
        UpdateFailure.offline: '連不上 GitHub，請稍後再試',
        UpdateFailure.refused: 'GitHub 現在沒有提供更新資訊，請稍後再試',
        UpdateFailure.unreadableFeed: '更新資訊看不懂',
        UpdateFailure.checkUnforeseen: '檢查更新時發生未預期的錯誤，已記在診斷，請稍後再試',
        UpdateFailure.absurdSize: '更新檔大小不合理，已取消下載',
        UpdateFailure.grewPastSize: '下載的檔案比預期大，已中止',
        UpdateFailure.downloadCut: '下載中斷，請稍後再試',
        UpdateFailure.damaged: '下載的檔案不完整，請再試一次',
        UpdateFailure.notThisApp: '這個更新檔不是「記帳本」的新版（套件、版本或簽章不符），已刪除，不會安裝',
        UpdateFailure.installUnforeseen: '更新時發生未預期的錯誤，已記在診斷，請稍後再試',
      },
    );
  });
}
