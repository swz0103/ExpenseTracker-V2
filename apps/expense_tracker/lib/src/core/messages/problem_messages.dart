import 'package:core/foundation_values.dart';
import 'package:flutter/services.dart';

import '../ledger/persistence/ledger_data_source.dart';
import '../ledger/persistence/quarantine.dart' show RowSetAside;
import '../ledger/ledger.dart'
    show
        KeepFailed,
        NameTaken,
        RecordRefused,
        ReloadFailed,
        StayedInBook,
        StayedInTrash;
import 'trash_messages.dart';
import 'validation_messages.dart';

// The one place an error becomes words on the screen (D84). An error the
// person can act on is said as what to do; any other is never said as it
// is (no exception, code, errno or path): one sentence of what did not
// happen, and where its details are. The caller has recorded the error
// in the ErrorLog, so the details are there to export.

/// Where a failure's details are, for the person to hand on.
const detailsInDiagnostics = '可在診斷匯出詳細資料';

/// Whether [note] sends the person to the diagnostics for its details:
/// where no settings can be reached, 匯出診斷 is offered beside it.
bool sendsToDiagnostics(String note) => note.contains(detailsInDiagnostics);

/// [what] did not happen, as one sentence with where its details are:
/// `failureNote('沒有存成圖片')` is 沒有存成圖片，可在診斷匯出詳細資料.
String failureNote(String what) => '$what，$detailsInDiagnostics';

/// [sentence] closed with 。, to have another sentence follow it: a
/// note of one sentence carries none (D81), one of several ends each.
String endSentence(String sentence) =>
    // Exception to sentence ends: the one place a sentence is closed.
    sentence.endsWith('。') ? sentence : '$sentence。';

/// Why [error] stopped a step, in words a person can act on; null when
/// it is not such an error, but a fault of the phone, its storage or the
/// app, which only [failureNote] tells.
String? actionableProblem(Object error) => switch (error) {
  KeepFailed(cause: DataSourceException(cause: RowSetAside())) ||
  DataSourceException(cause: RowSetAside()) => '這筆變更會覆蓋一筆讀不出來、已隔離的資料，為了保護它沒有存下',
  DataSourceException() || KeepFailed() => '帳本無法寫入，請重新打開 App 再試',
  ReloadFailed() => '帳本無法重新讀取，請重新打開 App；畫面上的內容可能與已儲存的不同',
  RecordRefused(:final first) => validationMessage(first),
  StayedInTrash(:final count) => stayedInTrashNote(count),
  StayedInBook(:final count) => stayedInBookNote(count),
  NameTaken() => '這個分類名稱已經有了，或是保留給「全部支出」「轉帳」等用途',
  MoneyException(code: MoneyError.precision) => '金額的小數位數太多',
  MoneyException() => '請輸入有效的金額',
  PlatformException(code: 'busy') => '上一個檔案還在處理，請稍候再試',
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

/// A step that runs by itself, out of sight, whose failure would go
/// unheard without a note (D84): told once a run of the app, in the note
/// at the foot of the screen, with where its details are.
enum QuietStep {
  /// The recurring items marked to book themselves, and what was
  /// confirmed on a notification.
  autoBooking('到期的定期交易沒有自動入帳'),

  /// The backup left for the background job, or what it delivered.
  backgroundBackup('背景備份沒有完成'),

  /// Closing prices and exchange rates.
  marketRefresh('收盤價與匯率沒有更新'),

  /// The due dates on the phone's calendar.
  calendarSync('提醒沒有同步到日曆'),

  /// The check, as the book opens, that no record names another the book
  /// no longer has: it found some, or could not finish.
  integrityCheck('帳本健檢沒有通過'),

  /// The photo the camera took while the phone closed the app, taken
  /// back for the next new entry.
  leftoverPhoto('相機拍的收據照片沒有找回'),

  /// Deleting the receipt photos no entry keeps any more.
  receiptSweep('不再使用的收據照片沒有清除');

  const QuietStep(this.what);

  /// What did not happen.
  final String what;

  /// The note the person reads.
  String get note => failureNote(what);
}
