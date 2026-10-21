import 'package:core/foundation_values.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'model/journal.dart';
import 'model/ledger.dart' show NameTaken, SharesShort;

/// Shows why a command was refused, in words a person can act on.
void showProblem(BuildContext context, Object error) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(describeProblem(error))));
}

String describeProblem(Object error) => switch (error) {
  JournalFailure() => '帳本無法寫入，請重新打開 App 再試。',
  SharesShort() => '這樣之後的賣出或減資會超過持股，請先改那一筆。',
  NameTaken() => '這個分類名稱已經有了，或是保留給「全部支出」「轉帳」等用途。',
  MoneyException(code: MoneyError.precision) => '金額的小數位數太多。',
  PlatformException(code: 'busy') => '上一個檔案還在處理，請稍候再試。',
  PlatformException() => '手機沒有完成這個動作，請再試一次。',
  MoneyException() || FormatException() => '請輸入有效的金額。',
  _ => '發生未預期的錯誤。',
};
