/// What 更新 says when an update is refused before it is installed: its
/// size, or the APK's package name, version code or signing certificate
/// (app_update.dart, UpdateGate.kt).
abstract final class UpdateMessages {
  /// The step named in the error log.
  static const downloadStep = '下載更新';

  /// update.json gives a size above the most an update may weigh.
  static const absurdSize = '更新檔大小不合理，已取消下載';

  /// The download went past the size update.json gave for it.
  static const grewPastSize = '下載的檔案比預期大，已中止';

  /// Android's side found an APK that is not a newer version of this app
  /// signed with the same key.
  static const notThisApp = '這個更新檔不是「記帳本」的新版（套件、版本或簽章不符），已刪除，不會安裝';
}
