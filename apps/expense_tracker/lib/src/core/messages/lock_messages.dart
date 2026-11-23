import '../platform/preferences.dart' show AutoLock;

/// The words of the lock: the wait after wrong passwords, the fingerprint,
/// auto-lock and hiding the screens.
abstract final class LockWords {
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

  /// The fingerprint could not open the ledger (not the person's own
  /// choice of the password, which says nothing).
  static const fingerprintFailed = '指紋解鎖失敗，請改用密碼';
  static const fingerprintNotYet = '先用密碼打開一次，之後就能用指紋解鎖';
  static const fingerprintStopped = '指紋解鎖已取消，可以改用密碼';
  static const fingerprintHeading = '指紋解鎖';
  static const fingerprintLabel = '用指紋或臉部解鎖';

  /// The diagnostics heading of a restore given up that could not reopen
  /// the ledger by itself.
  static const cancelRestoreHeading = '取消還原';

  /// 安全 › 指紋解鎖.
  static const fingerprint = '指紋解鎖';
  static const fingerprintOn = '已開啟 · 可用指紋或臉部打開帳本';
  static const fingerprintOff = '已關閉 · 只用密碼打開帳本';
  static const fingerprintTurnedOn = '已開啟指紋解鎖';
  static const fingerprintTurnedOff = '已關閉指紋解鎖';
  static const fingerprintNotTurned = '沒有完成，請再試一次';
  static const fingerprintSettingHeading = '指紋設定';

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
