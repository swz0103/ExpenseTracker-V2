// Exception to ledger words: what a failed unlock says is said here.

import 'dart:io';

import 'package:vault/backup_security.dart';
import 'package:vault/ledger_backup.dart';
import 'package:vault/ledger_vault.dart';

import '../../../core/diagnostics/error_log.dart';

/// What to tell the person when opening the ledger, or restoring a
/// backup, failed with [error]: by its kind, never the error as it is.
/// [recovery] when a recovery code was typed rather than the password.
/// One not foreseen is noted in the diagnostics log as well.
String unlockFailure(Object error, {required bool recovery}) => switch (error) {
  BackupException(:final problem) => '無法讀取這個備份（${problem.name}）',
  FileSystemException() => '找不到這個備份檔',
  VaultException(problem: VaultProblem.missingDatabase) =>
    '這台裝置上的帳本資料不見了，請從備份還原',
  VaultException(:final problem) => '無法開啟帳本（${problem.name}）',
  KeyringException(error: KeyringError.wrongSecret) =>
    recovery ? '救援碼不正確' : '密碼不正確',
  KeyringException(error: final kind) => '無法開啟帳本（${kind.name}）',
  _ => _unforeseen(error),
};

String _unforeseen(Object error) {
  ErrorLog.instance.record('還原備份', error);
  return '無法開啟帳本（${ErrorLog.describe(error)}）';
}
