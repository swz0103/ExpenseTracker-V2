import 'package:core/foundation_values.dart';
import 'package:flutter/services.dart';

import '../ledger/persistence/ledger_data_source.dart';
import '../ledger/persistence/quarantine.dart' show RowSetAside;
import '../ledger/ledger.dart'
    show KeepFailed, NameTaken, ReloadFailed, SharesShort;

/// Why a command was refused or a step failed, in words a person can act
/// on.
String describeProblem(Object error) => switch (error) {
  KeepFailed(cause: DataSourceException(cause: RowSetAside())) ||
  DataSourceException(
    cause: RowSetAside(),
  ) => '這筆變更會覆蓋一筆讀不出來、已隔離的資料，為了保護它沒有存下。',
  DataSourceException() || KeepFailed() => '帳本無法寫入，請重新打開 App 再試。',
  ReloadFailed() => '帳本無法重新讀取，請重新打開 App；畫面上的內容可能與保存的不同。',
  SharesShort() => '這樣之後的賣出或減資會超過持股，請先改那一筆。',
  NameTaken() => '這個分類名稱已經有了，或是保留給「全部支出」「轉帳」等用途。',
  MoneyException(code: MoneyError.precision) => '金額的小數位數太多。',
  PlatformException(code: 'busy') => '上一個檔案還在處理，請稍候再試。',
  PlatformException() => '手機沒有完成這個動作，請再試一次。',
  MoneyException() || FormatException() => '請輸入有效的金額。',
  _ => '發生未預期的錯誤。',
};
