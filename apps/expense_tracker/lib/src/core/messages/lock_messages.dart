import '../formatting/setting_topic.dart';
import 'key_messages.dart' show KeyWords;
import '../platform/preference_choices.dart' show AutoLock;

/// The words of the lock: the wait after wrong passwords, the fingerprint,
/// auto-lock and hiding the screens.
abstract final class LockWords {
  /// The book could not be opened, for a reason not the person's
  /// (problemNote adds where its details are).
  static const notOpened = '無法打開帳本';

  /// A new book could not be made.
  static const notCreated = '無法建立帳本';

  /// The backup chosen could not be downloaded.
  static const notDownloaded = '無法下載備份';

  /// Above the backups on Google Drive, to restore one.
  static const pickDriveBackup = '要還原哪一份備份';

  /// What the lock screen says while a wait after wrong tries is on, the
  /// time left counted down: 輸入錯誤太多次，請等 4 分 30 秒再試.
  static String waitFor(Duration wait) => '輸入錯誤太多次，請等 ${span(wait)}再試';

  /// [wait] in hours, minutes and seconds, a part left out when it is
  /// nothing, a started second counted whole: 1 小時, 4 分 30 秒, 30 秒.
  static String span(Duration wait) {
    // 1,000 ms to the second, 60 s to the minute, 60 min to the hour.
    final seconds = (wait.inMilliseconds + 999) ~/ 1000;
    final h = seconds ~/ 3600;
    final m = seconds % 3600 ~/ 60;
    final s = seconds % 60;
    return [
      if (h > 0) '$h 小時',
      if (m > 0) '$m 分',
      if (s > 0 || (h == 0 && m == 0)) '$s 秒',
    ].join(' ');
  }

  /// Making the book again on opening found the phone full (review 29):
  /// the book is as it was, and opens once there is room.
  static const noSpace = '手機空間不足，帳本還沒整理好。請先清出一些空間，再打開帳本';

  /// A backup not restored for want of room on the phone: the book here is
  /// as it was (review 30).
  static const restoreNoSpace = '手機空間不足，備份沒有還原，帳本維持原狀。請先清出一些空間，再試一次';

  /// The fingerprint could not open the ledger (not the person's own
  /// choice of the password, which says nothing).
  static const fingerprintFailed = '生物辨識解鎖失敗，請改用密碼';
  static const fingerprintNotYet = '先用密碼打開一次，之後就能用生物辨識解鎖';
  static const fingerprintStopped = '生物辨識解鎖已取消，可以改用密碼';
  static const fingerprintHeading = '生物辨識解鎖';

  /// The diagnostics heading of a restore given up that could not reopen
  /// the ledger by itself.
  static const cancelRestoreHeading = '取消還原';

  /// 安全 › 生物辨識解鎖.
  static const fingerprint = '生物辨識解鎖';
  static const fingerprintOn = '已開啟 · 可用生物辨識打開帳本';
  static const fingerprintOff = '已關閉 · 只用密碼打開帳本';
  static const fingerprintTurnedOn = '已開啟生物辨識解鎖';
  static const fingerprintTurnedOff = '已關閉生物辨識解鎖';
  static const fingerprintNotTurned = '沒有完成，請再試一次';
  static const fingerprintSettingHeading = '生物辨識設定';

  /// 安全 › 自動上鎖.
  static const autoLock = '自動上鎖';
  static final autoLockWhy =
      '離開 App 多久之後，回來要重新解鎖。拍收據、選檔案這類由 App 帶出去的畫面，'
      '至少 ${AutoLock.errand.inMinutes} 分鐘內不會上鎖。';

  /// What finds 自動上鎖 in the settings' search, beside its name.
  static const autoLockSearch = ['上鎖', '鎖定', '離開'];

  /// Under the 自動上鎖 card: the choice in force.
  static String autoLockDetail(AutoLock choice) => switch (choice) {
    AutoLock.immediately => '一離開 App 就上鎖',
    AutoLock.never => '只有關閉 App 後才需要解鎖',
    _ => '離開 ${choice.label}後上鎖',
  };

  /// 安全 › 禁止截圖.
  static const hideScreen = '禁止截圖';
  static const hideScreenOn = '截圖、錄影都擋下';
  static const hideScreenOff = '只有解鎖畫面擋下截圖';
  static const hideScreenHeading = '截圖設定';
  static const hideScreenFailed = '這支手機無法切換截圖設定';

  /// The diagnostics heading of locking that could not keep a change.
  static const lockHeading = '上鎖';
}

/// What search finds in SecuritySection (N8): each setting's name and the other
/// words a person may type for it, marking the card that section builds.
abstract final class SecurityTopics {
  static const password = SettingTopic('密碼', words: ['變更密碼', '設定密碼']);

  static const fingerprint = SettingTopic(
    LockWords.fingerprint,
    // Exception to glossary: search words: 指紋 finds the setting too.
    words: ['指紋', '臉部', '生物辨識'],
  );

  static const autoLock = SettingTopic(
    LockWords.autoLock,
    words: LockWords.autoLockSearch,
  );

  static const recovery = SettingTopic('救援碼', words: ['忘記密碼']);

  static const passphrase = SettingTopic(KeyWords.passphrase, words: ['備份']);

  static const hideScreen = SettingTopic(
    LockWords.hideScreen,
    words: ['截圖', '錄影', '隱私'],
  );

  static const reset = SettingTopic(KeyWords.reset, words: ['金鑰', '外流']);

  static const lockNow = SettingTopic('現在鎖上', words: ['鎖定']);
}
