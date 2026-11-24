import 'package:core/foundation_values.dart';
import 'package:flutter/services.dart';

import '../ledger/persistence/ledger_data_source.dart';
import '../ledger/persistence/quarantine.dart' show RowSetAside;
import '../ledger/ledger.dart'
    show KeepFailed, NameTaken, RecordRefused, ReloadFailed, StayedInTrash;
import 'trash_messages.dart';
import 'validation_messages.dart';

// The one place an error becomes words on the screen (D84). An error the
// person can act on is said as what to do; any other is never said as it
// is (no exception, code, errno or path): one sentence of what did not
// happen, and where its details are. The caller has recorded the error
// in the ErrorLog, so the details are there to export.

/// Where a failure's details are, for the person to hand on.
const detailsInDiagnostics = '可在診斷匯出詳細資料';

/// [what] did not happen, as one sentence with where its details are:
/// `failureNote('沒有存成圖片')` is 沒有存成圖片，可在診斷匯出詳細資料.
String failureNote(String what) => '$what，$detailsInDiagnostics';

/// Why [error] stopped a step, in words a person can act on; null when
/// it is not such an error, but a fault of the phone, its storage or the
/// app, which only [failureNote] tells.
String? actionableProblem(Object error) => switch (error) {
  KeepFailed(cause: DataSourceException(cause: RowSetAside())) ||
  DataSourceException(
    cause: RowSetAside(),
  ) => '這筆變更會覆蓋一筆讀不出來、已隔離的資料，為了保護它沒有存下。',
  DataSourceException() || KeepFailed() => '帳本無法寫入，請重新打開 App 再試。',
  ReloadFailed() => '帳本無法重新讀取，請重新打開 App；畫面上的內容可能與已儲存的不同。',
  RecordRefused(:final first) => validationMessage(first),
  StayedInTrash(:final count) => stayedInTrashNote(count),
  NameTaken() => '這個分類名稱已經有了，或是保留給「全部支出」「轉帳」等用途。',
  MoneyException(code: MoneyError.precision) => '金額的小數位數太多。',
  MoneyException() => '請輸入有效的金額。',
  PlatformException(code: 'busy') => '上一個檔案還在處理，請稍候再試。',
  _ => null,
};

/// Why a command was refused or a step failed, as a sentence of its own:
/// what to do, or that it was not done and where the details are.
String describeProblem(Object error) =>
    actionableProblem(error) ?? failureNote('沒有完成這個動作');

/// [what] did not happen because of [error], in one line: `what：` and
/// what to do when the person can act on it, otherwise [failureNote].
String problemNote(String what, Object error) =>
    switch (actionableProblem(error)) {
      final said? => '$what：$said',
      null => failureNote(what),
    };
