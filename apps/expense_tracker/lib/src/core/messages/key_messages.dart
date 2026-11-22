import 'dart:io';

import 'package:vault/backup_security.dart';
import 'package:vault/ledger_backup.dart';
import 'package:vault/ledger_vault.dart';

import '../diagnostics/error_log.dart';
import '../formatting/dates.dart';

/// The words of the ledger's keys, in one place: passwords and their rule,
/// the recovery code, the backup passphrase, resetting the keys, and what
/// a failed unlock or restore says. The rule itself is the vault's
/// [PasswordPolicy.standard]; these only say it.
const _policy = PasswordPolicy.standard;

/// Under the fields where a password or backup passphrase is set.
final passwordRule = '至少 ${_policy.minimumLength} 個字，不能全是數字';

/// Why [password] cannot be set, or null when it can.
String? passwordRefusal(String password) => switch (_policy.check(password)) {
  PasswordProblem.tooShort => '至少要 ${_policy.minimumLength} 個字',
  PasswordProblem.allDigits => '不能全是數字，請加上文字或符號',
  null => null,
};

/// Whether a password in use is shorter or simpler than one set today
/// may be; it keeps working, and the settings suggest changing it.
bool passwordBelowRule(String password) => _policy.isBelow(password);

/// What a password, passphrase or recovery code change that failed says,
/// by its kind: the current password typed wrong, or a new one against
/// the rule.
String describeKeyProblem(Object error) => switch (error) {
  KeyringException(error: KeyringError.wrongSecret) => '目前的密碼不正確',
  KeyringException(
    error: KeyringError.weakPassword,
    passwordProblem: final problem,
  ) =>
    switch (problem) {
      PasswordProblem.allDigits => '不能全是數字，請加上文字或符號',
      _ => '至少要 ${_policy.minimumLength} 個字',
    },
  _ => '沒有完成（${ErrorLog.describe(error)}）',
};

/// What to tell the person when opening the ledger, or restoring a
/// backup, failed with [error]: by its kind, in words, never an internal
/// code. [recovery] when the recovery code (or backup passphrase) was
/// typed rather than the password. One not foreseen is noted in the
/// diagnostics log as well.
String describeUnlockFailure(Object error, {required bool recovery}) =>
    switch (error) {
      BackupException(:final problem) => switch (problem) {
        BackupProblem.invalidFormat => '這個檔案不是完整的記帳本備份，可能已損毀或沒有下載完',
        BackupProblem.unsupportedVersion => '這個備份是較新版本的 App 做的，請先更新 App',
        BackupProblem.authenticationFailed => '打不開這個備份：輸入的不是它的救援碼或密碼，或檔案被改過',
        BackupProblem.targetNotEmpty => '這台手機上已經有帳本了',
        BackupProblem.invalidContent => '這個備份裡有 App 讀不懂的資料，沒有還原',
      },
      FileSystemException() => '找不到這個備份檔',
      VaultException(:final problem) => switch (problem) {
        VaultProblem.missingDatabase => '這台裝置上的帳本資料不見了，請從備份還原',
        VaultProblem.missing => '這台手機上還沒有帳本',
        VaultProblem.alreadyExists => '這台手機上已經有帳本了',
        VaultProblem.damagedKeyring => '帳本的金鑰檔損毀，請從備份還原',
        VaultProblem.otherLedger => '這不是這本帳本的金鑰',
        VaultProblem.damagedRestore => '備份沒有通過檢查，帳本維持原狀',
      },
      KeyringException(error: KeyringError.wrongSecret) =>
        recovery ? '救援碼不正確' : '密碼不正確',
      KeyringException(error: KeyringError.invalidFormat) =>
        recovery ? '救援碼的格式不對，請檢查是否少打或打錯字' : '帳本的金鑰檔無法讀取，請從備份還原',
      KeyringException(error: KeyringError.unsupportedVersion) =>
        '這本帳本是較新版本的 App 做的，請先更新 App',
      KeyringException(error: KeyringError.noSuchSlot) =>
        recovery ? '這裡沒有設定備份密碼，請輸入救援碼' : '這本帳本沒有密碼，請改用救援碼',
      KeyringException(error: KeyringError.unknownDevice) =>
        '這台手機還不能用指紋打開，請改用密碼',
      KeyringException(error: KeyringError.weakPassword) => describeKeyProblem(
        error,
      ),
      _ => _unforeseen(error),
    };

String _unforeseen(Object error) {
  ErrorLog.instance.record('還原備份', error);
  return '無法開啟帳本（${ErrorLog.describe(error)}）';
}

/// When a backup was taken and how many records it holds.
String describeBackup(BackupHeader header) =>
    '${formatYMdHm(header.createdAt.toLocal())} 的備份 · ${header.rows} 筆資料';

/// What opens the backup [header] describes, said on the restore form.
String restoreNeeds(BackupHeader header) => header.keyring.hasPassword
    ? '輸入那本帳本的密碼或救援碼。'
    : header.keyring.hasPassphrase
    ? '這份備份要用救援碼或備份密碼打開（不是 App 的密碼）。'
    : '這份備份要用救援碼打開（不是 App 的密碼）。';

/// The label of a ledger kept before a restore, by when the backup it is
/// was taken; [header] null when it cannot be read.
String keptLabel(BackupHeader? header, {required bool broughtBack}) {
  if (header == null) return '無法讀取的備份';
  final at = formatYMdHm(header.createdAt.toLocal());
  final from = broughtBack ? '（Google 系統備份帶回）' : '';
  return '$at 的帳本 · ${header.rows} 筆$from';
}

/// The warning before a backup replaces a ledger with more records, or a
/// newer state of the same ledger: both dates and counts.
String olderBackupWarning(BackupHeader backup, BackupHeader current) =>
    '要還原的備份比目前的帳本舊或筆數較少：\n'
    '目前的帳本：${current.rows} 筆（${formatYMdHm(current.createdAt.toLocal())} 留下一份）\n'
    '要還原的備份：${backup.rows} 筆（${formatYMdHm(backup.createdAt.toLocal())}）\n'
    '還原後，目前帳本裡較新的資料會被換掉。確定要還原嗎？';

/// Whether [backup] would replace [current] with less: an earlier state of
/// the same ledger, or fewer records.
bool backupIsOlder(BackupHeader backup, BackupHeader current) =>
    (backup.keyring.id == current.keyring.id &&
        backup.revision < current.revision) ||
    backup.rows < current.rows;

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
