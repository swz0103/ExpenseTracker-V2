/// The words of the key settings and the screens about keys.
abstract final class KeyWords {
  static const setPassword = '設定密碼';
  static const changePassword = '變更密碼';
  static const currentPassword = '目前的密碼';
  static const newPassword = '新密碼';
  static const again = '再輸入一次';
  static const mismatch = '兩次輸入的新密碼不一樣';
  static const set = '設定';
  static const change = '變更';
  static const passwordSet = '已設定密碼';
  static const passwordChanged = '密碼已變更';

  /// What a changed password does, and does not do.
  static const passwordScope = '新密碼用於之後的解鎖與之後的備份。已經存在的舊備份不會改變，仍可用當時的密碼或救援碼打開。';
  static const passwordFirstWhy = '密碼設好了。忘記密碼時，只有它能打開帳本';
  static const passwordBelowRule = '目前的密碼比現在的規定短或太簡單，仍可使用，建議變更';

  static const recoveryConfirm = '換一組新的救援碼？之後的解鎖與之後的備份只認新的；已經存在的舊備份仍可用舊的救援碼打開。';
  static const replace = '更換';
  static const notReplaced = '沒有換成：';
  static const notDone = '沒有完成，請再試一次';

  /// A failed unlock or restore not foreseen: its diagnostics heading,
  /// and what is said, with [detail] (ErrorLog.describe).
  static const unforeseenHeading = '還原備份';
  static String unforeseen(String detail) => '無法開啟帳本（$detail）';

  static const passphrase = '備份密碼';
  static const passphraseOn = '已設定 · 備份可用它或救援碼打開';
  static const passphraseOff = '沒有設定 · 備份只能用救援碼打開';
  static const passphraseWhy =
      '另設一組只用來打開備份的密碼（不是 App 的密碼）。設定後，之後的備份可以用它或救援碼還原。';
  static const passphraseSet = '已設定備份密碼，之後的備份可以用它還原';
  static const passphraseRemove = '不再使用備份密碼？之後的備份只能用救援碼還原；已經存在的備份不受影響。';
  static const passphraseRemoved = '已停用備份密碼';
  static const remove = '停用';

  static const reset = '重設金鑰';
  static const resetDetail = '懷疑密碼或救援碼外流時使用';
  static const resetWhy =
      '換掉帳本的全部金鑰：資料庫與收據照片重新加密，產生新的救援碼，之後的備份改用新的金鑰。'
      '完成後，舊的密碼檔與舊救援碼再也打不開這台手機上的帳本。\n\n'
      '但已經存在的舊備份（雲端硬碟、資料夾、Google 系統備份、匯出的檔案）仍可用當時的密碼或救援碼打開，'
      '若懷疑外流，請自行刪除它們。指紋解鎖與備份密碼需要重新設定。';
  static const resetGo = '重設';
  static const resetDone = '金鑰已重設。舊的救援碼不再適用，請抄下新的';

  static const newPasswordTitle = '設定新的密碼';
  static const newPasswordWhy = '帳本是用救援碼或備份密碼打開的，請設定新的密碼。設定好之前，原本的密碼（如果有）仍然有效。';
  static const noPassword = '改成打開 App 不需要密碼';
  static const noPasswordConfirm =
      '不設定密碼？之後打開 App 不需要任何驗證，拿到這支手機的人就能看到帳本。原本的密碼會失效。';
  static const noPasswordGo = '不需要密碼';

  static const olderBackup = '備份比較舊';
  static const restoreAnyway = '仍要還原';

  static const recoveryOrPassphrase = '救援碼或備份密碼';
  static const recoveryCode = '救援碼';
  static const restoreHint = '輸入備份檔的位置，和那個帳本的密碼或救援碼。';
  static const recoveryHint = '輸入建立帳本時拿到的救援碼。';
  static const recoveryOrPassphraseHint = '輸入救援碼，或你設定的備份密碼。';
}
