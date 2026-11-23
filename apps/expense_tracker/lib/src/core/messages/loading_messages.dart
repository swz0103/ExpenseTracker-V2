import '../formatting/words.dart';
import '../ledger/persistence/quarantine.dart';

// What opening the book tells the person: rows set aside, and a book that
// could not be opened at all; and the diagnostics either one exports.

/// The title of the notice of rows set aside as the book opened.
String quarantineTitle(int count) => '有 $count 筆資料讀不出來，已先隔離';

/// What the notice says of [rows]: what happened to them, and what is
/// safe to do.
String quarantineBody(List<QuarantinedRow> rows) {
  final newer = rows.where((r) => r.reason == QuarantineReason.newer).length;
  final lines = [
    '其他資料都已正常打開。這些資料原封不動留在手機上，這個版本不會改寫或刪除它們。',
    if (newer > 0) '其中 $newer 筆由較新版本寫入，請更新 App 到最新版本後再打開。',
    if (newer < rows.length) '可以匯出診斷資料回報問題，或從備份還原。',
  ];
  return lines.join('\n\n');
}

/// The words of each reason a row is set aside.
String quarantineReason(QuarantinedRow row) => switch (row.reason) {
  QuarantineReason.unreadable => '讀不出來',
  QuarantineReason.newer => '由較新版本寫入（第 ${row.version} 版）',
  QuarantineReason.invalid => '內容不完整',
};

/// The words of each kind of row.
String _shelf(String shelf) => switch (shelf) {
  'account' => Words.account,
  'category' => Words.category,
  'entry' => '紀錄',
  'budget' => '預算',
  'recurring' => '定期項目',
  'trash' => '最近刪除',
  _ => shelf,
};

const quarantineExport = '匯出診斷';
const quarantineRestore = '還原備份';
const quarantineContinue = '繼續使用';
const quarantineExported = '已匯出診斷資料';

/// The book could not be opened at all.
const loadFailedTitle = '帳本打不開';
const loadFailedBody = '讀取帳本時發生問題，資料沒有被改動。可以再試一次；如果一直打不開，可以從備份還原，或匯出診斷資料回報問題。';
const loadFailedRetry = '再試一次';
const loadFailedRestore = '從備份還原';
const loadFailedExport = '匯出診斷';

/// The app could not start at all, `what` having failed (already
/// cleaned of what the person wrote).
const startFailedTitle = '記帳本無法啟動';
String startFailedBody(String what) =>
    '啟動時發生問題（$what），資料沒有被改動。可以再試一次；如果一直無法啟動，可以複製診斷資料回報問題。';
const startFailedCopy = '複製診斷資料';
const startFailedCopied = '已複製診斷資料';

/// The name of the diagnostics file of an opening.
const openingReportName = '記帳本-開啟診斷.txt';

/// The diagnostics of an opening, to export: which rows were set aside
/// and why, or what stopped the book opening ([failure], already cleaned
/// of what the person wrote), then [log], the diagnostics log. Never an
/// amount, a note or a name from a row.
String openingReport({
  List<QuarantinedRow> rows = const [],
  String? failure,
  String log = '',
}) => [
  '記帳本 開啟診斷',
  if (failure != null) '無法開啟：$failure',
  if (rows.isNotEmpty) '隔離的資料：${rows.length} 筆',
  for (final row in rows)
    '${_shelf(row.shelf)} ${row.key}：${quarantineReason(row)}'
        '${row.detail.isEmpty ? '' : '（${row.detail}）'}',
  if (log.isNotEmpty) ...['', '診斷紀錄', log],
].join('\n');
