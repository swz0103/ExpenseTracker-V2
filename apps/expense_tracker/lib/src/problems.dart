import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:foundation_values/foundation_values.dart';

/// Shows why a command was refused, in words a person can act on.
void showProblem(BuildContext context, Object error) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(describeProblem(error))));
}

String describeProblem(Object error) => switch (error) {
  AppFailure(diagnostic: 'account.versionConflict') => '帳戶剛被修改過，請再試一次。',
  AppFailure(diagnostic: 'account.unavailable') => '這個帳戶已封存或結清，不能記帳。',
  AppFailure(diagnostic: 'account.invalidInput') => '帳戶名稱不能空白，最多 100 字。',
  AppFailure(diagnostic: 'ledger.invalidAmount') => '金額必須大於 0。',
  AppFailure(diagnostic: 'ledger.sameAccount') => '轉出與轉入不能是同一個帳戶。',
  AppFailure(diagnostic: 'posting.already-reversed') => '這筆已經沖銷過了。',
  AppFailure(:final diagnostic) => '無法完成（$diagnostic）。',
  MoneyException(code: MoneyError.precision) => '金額的小數位數太多。',
  MoneyException() || FormatException() => '請輸入有效的金額。',
  _ => '發生未預期的錯誤。',
};
