/// The words of the key settings and the screens about keys.
abstract final class KeyWords {
  /// The heading of the chooser of ledgers kept before a restore.
  static const keptLedgers = '還原前自動留下的帳本';
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

  /// The diagnostics heading of a failed unlock or restore not foreseen.
  static const unforeseenHeading = '還原備份';

  /// What such a failure says, with [detail] (`ErrorLog.describe`).
  static String unforeseen(String detail) => '無法打開帳本（$detail）';

  static const passphrase = '備份密碼';
  static const passphraseOn = '已設定 · 備份可用它或救援碼打開';
  static const passphraseOff = '沒有設定 · 備份只能用救援碼打開';
  static const passphraseWhy =
      '另設一組只用來打開備份的密碼（不是 App 的密碼）。設定後，之後的備份可以用它或救援碼還原。'
      '拿到備份檔的人可以一直猜，所以要比 App 的密碼長，例如用幾個不相關的詞組成一句。';
  static const passphraseSet = '已設定備份密碼，之後的備份可以用它還原';
  static const passphraseRemove = '不再使用備份密碼？之後的備份只能用救援碼還原；已經存在的備份不受影響。';
  static const passphraseRemoved = '已停用備份密碼';
  static const remove = '停用';

  static const reset = '重設金鑰';
  static const resetDetail = '懷疑密碼或救援碼外流時使用';
  static const resetWhy =
      '換掉帳本的全部金鑰：資料庫與收據照片重新加密，產生新的救援碼，之後的備份改用新的金鑰。'
      '完成後，舊的密碼檔與舊救援碼再也打不開這台手機上的帳本。\n\n'
      '但已經存在的舊備份（雲端硬碟、資料夾、Google 系統備份、匯出的檔案）仍可用當時的密碼或救援碼打開。'
      '完成後會列出這支手機與雲端硬碟上的舊備份，確認後可刪除；其他地方的請自行刪除。生物辨識解鎖與備份密碼需要重新設定。';
  static const resetGo = '重設';
  static const resetDone = '金鑰已重設。舊的救援碼不再適用，請抄下新的';

  /// After a reset (D15): the backups still sealed with the old keys.
  static const oldBackupsTitle = '刪除舊金鑰的備份？';

  /// What was found, by where, each with how many and their dates.
  static String oldBackupsBody({
    required List<String> drive,
    required List<String> phone,
    required bool driveUnreached,
  }) => [
    '這些備份是重設前用舊金鑰做的，用舊的密碼或救援碼仍打得開。',
    if (drive.isNotEmpty)
      'Google 雲端硬碟：${drive.length} 份（${drive.join('、')}），$oldBackupsToTrash',
    if (phone.isNotEmpty) '這支手機：${phone.length} 份（${phone.join('、')}），會直接刪除',
    if (driveUnreached) oldBackupsUnreached,
    '資料夾、匯出的檔案與 Google 系統備份裡的舊備份不在此列，請自行處理。',
  ].join('\n\n');
  static const oldBackupsGo = '刪除舊備份';

  /// What becomes of the old backups on Drive (decided: the Drive trash,
  /// recoverable until Drive empties it).
  static const oldBackupsToTrash = '移到雲端硬碟的垃圾桶，30 天後自動刪除';
  static const oldBackupsUnreached = '連不上 Google 雲端硬碟，那裡的舊備份沒有列出，可以之後自行刪除';
  static String oldBackupsGone(int count) => '已刪除 $count 份舊金鑰的備份';

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
