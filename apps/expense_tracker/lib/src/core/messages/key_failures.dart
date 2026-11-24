import 'dart:io';

import 'package:storage/storage.dart' show StorageProblem, StorageUnavailable;
import 'package:vault/backup_security.dart';
import 'package:vault/ledger_backup.dart';
import 'package:vault/ledger_vault.dart';

import '../../../design_system/display/amount.dart';
import '../../../design_system/display/date.dart';
import '../platform/startup.dart' show UnlockDelayed;
import 'lock_messages.dart';

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

/// What a password, passphrase or key change that failed says, by its
/// kind: the current password typed wrong, or a new one against the rule.
/// One not foreseen gets general words; the caller notes it for
/// diagnostics.
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
  _ => '沒有完成，請再試一次',
};

/// The words for a change the keys refused ([KeyringException]), or null
/// for any other failure.
String? keyRefusal(Object error) =>
    error is KeyringException ? describeKeyProblem(error) : null;

/// What to tell the person when opening the ledger, or restoring a
/// backup, failed with [error]: by its kind, in words, never an internal
/// code. [recovery] when the recovery code (or backup passphrase) was
/// typed rather than the password. Null for one not foreseen, which the
/// caller notes for diagnostics and words itself.
String? describeUnlockFailure(Object error, {required bool recovery}) =>
    switch (error) {
      BackupException(:final problem) => switch (problem) {
        BackupProblem.invalidFormat => '這個檔案不是完整的記帳本備份，可能已損毀或沒有下載完',
        BackupProblem.unsupportedVersion => '這個備份是較新版本的 App 做的，請先更新 App',
        BackupProblem.authenticationFailed => '打不開這個備份：輸入的不是它的救援碼或密碼，或檔案被改過',
        BackupProblem.targetNotEmpty => '這台手機上已經有帳本了',
        BackupProblem.invalidContent => '這個備份裡有 App 讀不懂的資料，沒有還原',
      },
      // Not tried at all: too many wrong ones came before it.
      UnlockDelayed(:final wait) => LockWords.waitFor(wait),
      FileSystemException() => '找不到這個備份檔',
      StorageUnavailable(problem: StorageProblem.damaged) => '帳本檔案已損毀，請從備份還原',
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
        '這台手機還不能用生物辨識打開，請改用密碼',
      KeyringException(error: KeyringError.weakPassword) => describeKeyProblem(
        error,
      ),
      _ => null,
    };

/// When a backup was taken and how many records it holds.
String describeBackup(BackupHeader header) =>
    '${formatYMdHm(header.createdAt.toLocal())} 的備份 · ${countOf(header.rows, CountUnit.entries)}資料';

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
  return '$at 的帳本 · ${countOf(header.rows, CountUnit.entries)}$from';
}

/// The warning before a backup replaces a ledger with more records, or a
/// newer state of the same ledger: both dates and counts.
String olderBackupWarning(BackupHeader backup, BackupHeader current) =>
    '要還原的備份比目前的帳本舊或筆數較少：\n'
    '目前的帳本：${countOf(current.rows, CountUnit.entries)}（${formatYMdHm(current.createdAt.toLocal())} 留下一份）\n'
    '要還原的備份：${countOf(backup.rows, CountUnit.entries)}（${formatYMdHm(backup.createdAt.toLocal())}）\n'
    '還原後，目前帳本裡較新的資料會被換掉。確定要還原嗎？';

/// Whether [backup] would replace [current] with less: an earlier state of
/// the same ledger, or fewer records.
bool backupIsOlder(BackupHeader backup, BackupHeader current) =>
    (backup.keyring.id == current.keyring.id &&
        backup.revision < current.revision) ||
    backup.rows < current.rows;
