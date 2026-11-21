import 'dart:io';

import 'package:expense_tracker/src/core/diagnostics/error_log.dart';
import 'package:expense_tracker/src/features/lock/model/unlock_failure.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vault/backup_security.dart';
import 'package:vault/ledger_backup.dart';
import 'package:vault/ledger_vault.dart';

/// What a failed unlock or restore says: by its kind, never the error as
/// it is; one not foreseen is noted for diagnostics too.
void main() {
  String say(Object error, {bool recovery = false}) =>
      unlockFailure(error, recovery: recovery);

  test('a wrong secret names which one', () {
    const wrong = KeyringException(KeyringError.wrongSecret);
    expect(say(wrong), '密碼不正確');
    expect(say(wrong, recovery: true), '救援碼不正確');
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
      '無法讀取這個備份（invalidFormat）',
    );
    expect(say(const FileSystemException('gone')), '找不到這個備份檔');
  });

  test('one not foreseen is said without its words, and noted', () {
    final before = ErrorLog.instance.entries.length;
    final said = say(StateError('at /data/user/0/secret/path 1234'));
    expect(said, startsWith('無法開啟帳本（'));
    expect(said, isNot(contains('/data/user')));
    expect(ErrorLog.instance.entries.length, before + 1);
  });
}
