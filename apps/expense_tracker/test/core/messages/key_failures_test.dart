import 'dart:io';

import 'package:expense_tracker/src/core/messages/key_failures.dart';
import 'package:expense_tracker/src/core/platform/startup.dart'
    show UnlockDelayed;
import 'package:flutter_test/flutter_test.dart';
import 'package:storage/storage.dart'
    show SqliteException, StorageProblem, StorageUnavailable;
import 'package:vault/backup_security.dart';
import 'package:vault/ledger_backup.dart';
import 'package:vault/ledger_vault.dart';

/// What a failed unlock or restore says: by its kind, in words, never the
/// error as it is or an internal code; one not foreseen is left to the
/// caller.
void main() {
  test('a try not made for the wait after wrong ones says how long', () {
    for (final recovery in [true, false]) {
      expect(
        describeUnlockFailure(
          const UnlockDelayed(Duration(minutes: 4, seconds: 30)),
          recovery: recovery,
        ),
        '輸入錯誤太多次，請等 4 分 30 秒再試',
      );
    }
  });

  String? say(Object error, {bool recovery = false}) =>
      describeUnlockFailure(error, recovery: recovery);

  test('a file too large to be a backup says so (R12)', () {
    expect(
      say(const BackupException(BackupProblem.tooLarge)),
      '這個檔案超過 4 GB，不是記帳本的備份',
    );
  });

  test('a damaged ledger file is not a wrong password (D94)', () {
    const damaged = StorageUnavailable(StorageProblem.damaged);
    expect(say(damaged), '帳本檔案已損毀，請從備份還原');
    expect(say(damaged, recovery: true), '帳本檔案已損毀，請從備份還原');
    expect(say(const StorageUnavailable(StorageProblem.wrongKey)), isNull);
  });

  test('a wrong secret names which one', () {
    const wrong = KeyringException(KeyringError.wrongSecret);
    expect(say(wrong), '密碼不正確');
    expect(say(wrong, recovery: true), '救援碼不正確');
  });

  test('a recovery code typed wrong is said in words, never invalidFormat '
      '(F98)', () {
    const malformed = KeyringException(KeyringError.invalidFormat);
    expect(say(malformed, recovery: true), '救援碼的格式不對，請檢查是否少打或打錯字');
    for (final kind in KeyringError.values) {
      for (final recovery in [false, true]) {
        final said = say(KeyringException(kind), recovery: recovery);
        expect(said, isNot(contains(kind.name)), reason: kind.name);
      }
    }
    for (final problem in BackupProblem.values) {
      expect(
        say(BackupException(problem)),
        isNot(contains(problem.name)),
        reason: problem.name,
      );
    }
    for (final problem in VaultProblem.values) {
      expect(
        say(VaultException(problem)),
        isNot(contains(problem.name)),
        reason: problem.name,
      );
    }
  });

  test('the book gone from the phone points to a backup', () {
    expect(
      say(const VaultException(VaultProblem.missingDatabase)),
      '這台裝置上的帳本資料不見了，請從備份還原',
    );
  });

  test('a backup that cannot be read, or is not there', () {
    expect(
      say(const BackupException(BackupProblem.invalidFormat)),
      '這個檔案不是完整的記帳本備份，可能已損毀或沒有下載完',
    );
    expect(say(const FileSystemException('gone')), '找不到這個備份檔');
  });

  test('a backup without a passphrase, opened by something else', () {
    const none = KeyringException(KeyringError.noSuchSlot);
    expect(say(none, recovery: true), '這裡沒有設定備份密碼，請輸入救援碼');
    expect(say(none), '這本帳本沒有密碼，請改用救援碼');
  });

  test('one not foreseen is left to the caller', () {
    expect(say(StateError('at /data/user/0/secret/path 1234')), isNull);
  });

  group('the password rule (SEC-02, SEC-13)', () {
    test('is said from the vault\'s one policy', () {
      // PasswordPolicy.standard: 8 characters, not digits alone.
      expect(passwordRule, '至少 8 個字，不能全是數字');
      expect(passwordRefusal('1234567'), '至少要 8 個字');
      expect(passwordRefusal('12345678'), '不能全是數字，請加上文字或符號');
      expect(passwordRefusal('apple pie'), isNull);
    });

    test('a failed change is said by the error\'s kind, not its words', () {
      expect(
        describeKeyProblem(const KeyringException(KeyringError.wrongSecret)),
        '目前的密碼不正確',
      );
      expect(
        describeKeyProblem(
          const KeyringException(
            KeyringError.weakPassword,
            passwordProblem: PasswordProblem.allDigits,
          ),
        ),
        '不能全是數字，請加上文字或符號',
      );
      expect(
        describeKeyProblem(
          const KeyringException(
            KeyringError.weakPassword,
            passwordProblem: PasswordProblem.tooShort,
          ),
        ),
        '至少要 8 個字',
      );
      // A refused passphrase says the passphrase rule's minimum.
      expect(
        describeKeyProblem(
          const KeyringException(
            KeyringError.weakPassword,
            passwordProblem: PasswordProblem.tooShort,
            minimumLength: 12,
          ),
        ),
        '至少要 12 個字',
      );
      // A StateError that merely mentions the word is not taken for it.
      expect(describeKeyProblem(StateError('wrongSecret')), '沒有完成，請再試一次');
      expect(keyRefusal(StateError('wrongSecret')), isNull);
      expect(
        keyRefusal(const KeyringException(KeyringError.wrongSecret)),
        '目前的密碼不正確',
      );
    });
  });

  group('the backup passphrase rule (review 22 finding 1)', () {
    test('is stricter than the password rule', () {
      // PasswordPolicy.passphrase: 12 characters, not digits alone.
      expect(passphraseRule, '至少 12 個字，不能全是數字');
      // 11 characters ("apple pie 1") pass as a password, not here.
      expect(passwordRefusal('apple pie 1'), isNull);
      expect(passphraseRefusal('apple pie 1'), '至少要 12 個字');
      expect(passphraseRefusal('123456789012'), '不能全是數字，請加上文字或符號');
      expect(passphraseRefusal('apple pie 12'), isNull);
    });
  });

  test('a full phone is said as such for a database refused too, and a '
      'restore says the backup was not restored (review 30)', () {
    const file = FileSystemException(
      'write',
      'keyring.json.new',
      OSError('No space left on device', 28),
    );
    // 13 is SQLITE_FULL.
    final database = SqliteException(extendedResultCode: 13, message: 'full');
    for (final full in <Object>[file, database]) {
      expect(say(full), '手機空間不足，帳本還沒整理好。請先清出一些空間，再打開帳本');
      expect(
        describeTry(full, recovery: false, restore: false),
        '手機空間不足，帳本還沒整理好。請先清出一些空間，再打開帳本',
      );
      expect(
        describeTry(full, recovery: true, restore: true),
        '手機空間不足，備份沒有還原，帳本維持原狀。請先清出一些空間，再試一次',
      );
      // Found by the fingerprint's opening: said as such, and not kept
      // as the fingerprint's fault (noted where the book is made again).
      expect(describeDeviceFailure(full), (
        words: '手機空間不足，帳本還沒整理好。請先清出一些空間，再打開帳本',
        kept: false,
      ));
    }
    // Anything else in a restore is said as for an opening.
    const wrong = KeyringException(KeyringError.wrongSecret);
    expect(describeTry(wrong, recovery: true, restore: true), '救援碼不正確');
    expect(
      describeTry(
        const FileSystemException('open'),
        recovery: true,
        restore: true,
      ),
      '找不到這個備份檔',
    );
  });

  test('a fingerprint that fails says why, and keeps what is its fault', () {
    expect(
      describeDeviceFailure(const KeyringException(KeyringError.unknownDevice)),
      (words: '先用密碼打開一次，之後就能用生物辨識解鎖', kept: false),
    );
    expect(
      describeDeviceFailure(const KeyringException(KeyringError.wrongSecret)),
      (words: '生物辨識解鎖失敗，請改用密碼', kept: true),
    );
    expect(describeDeviceFailure(StateError('cancelled')), (
      words: '生物辨識解鎖已取消，可以改用密碼',
      kept: true,
    ));
  });
}
