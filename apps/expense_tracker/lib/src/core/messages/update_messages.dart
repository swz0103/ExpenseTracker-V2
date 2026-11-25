import '../formatting/setting_topic.dart';
import '../../../design_system/display/amount.dart';
import '../platform/update_status.dart';

/// What 更新 says: how this build stands against the newest, and why a
/// look or a download did not work (app_update.dart, UpdateGate.kt).
abstract final class UpdateMessages {
  /// The step named in the error log when looking fails.
  static const checkStep = '檢查更新';

  /// Stops the download of an update under way (D85).
  static const cancelDownload = '取消下載';

  /// The step named in the error log when the download fails.
  static const downloadStep = '下載更新';

  /// update.json gives a size above the most an update may weigh.
  static const absurdSize = '更新檔大小不合理，已取消下載';

  /// The download went past the size update.json gave for it.
  static const grewPastSize = '下載的檔案比預期大，已中止';

  /// Android's side found an APK that is not a newer version of this app
  /// signed with the same key.
  static const notThisApp = '這個更新檔不是「記帳本」的新版（套件、版本或簽章不符），已刪除，不會安裝';

  /// Why a look or a download did not work, in words to act on.
  static String failure(UpdateFailure failure) => switch (failure) {
    UpdateFailure.offline => '連不上 GitHub，請稍後再試',
    UpdateFailure.refused => 'GitHub 現在沒有提供更新資訊，請稍後再試',
    UpdateFailure.unreadableFeed => '更新資訊看不懂',
    UpdateFailure.checkUnforeseen => '檢查更新時發生未預期的錯誤，已記在診斷，請稍後再試',
    UpdateFailure.absurdSize => absurdSize,
    UpdateFailure.grewPastSize => grewPastSize,
    UpdateFailure.downloadCut => '下載中斷，請稍後再試',
    UpdateFailure.damaged => '下載的檔案不完整，請再試一次',
    UpdateFailure.notThisApp => notThisApp,
    UpdateFailure.installUnforeseen => '更新時發生未預期的錯誤，已記在診斷，請稍後再試',
  };

  /// What 關於 says under a build Google Play updates (the play flavor):
  /// only who updates it, nothing else about updates.
  static const byGooglePlay = '由 Google Play 更新';

  /// What 關於 says under this build's [version] (empty when the build
  /// has none).
  static String status(UpdateStatus status, {required String version}) =>
      switch (status) {
        UpdateNotOffered() => byGooglePlay,
        UpdateHandBuilt() => '自行建置的版本',
        UpdateNotLooked() => '點這裡檢查更新',
        UpdateChecking() => '檢查中…',
        UpdateCurrent() => version.isEmpty ? '已是最新版本' : '已是最新版本（$version）',
        UpdateAvailable(version: final newer) => '有新版 $newer',
        UpdateDownloading(:final share) => '下載中 ${ratioWholePercent(share)}',
        UpdateFailed(failure: final why) => failure(why),
      };
}

/// What search finds in AboutSection (N8): each setting's name and the other
/// words a person may type for it, marking the card that section builds.
abstract final class AboutTopics {
  static const version = SettingTopic('版本與更新', words: ['新版', '版本']);

  static const updates = SettingTopic('自動檢查新版本', words: ['更新', '版本']);

  static const diagnostics = SettingTopic('診斷', words: ['錯誤', '效能']);

  static const sampleReset = SettingTopic('重設範例資料', words: ['範例']);
}
