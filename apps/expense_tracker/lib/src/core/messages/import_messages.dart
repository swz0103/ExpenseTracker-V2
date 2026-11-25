import '../formatting/setting_topic.dart';

import 'package:domain/data_exchange.dart'
    show
        DayProblem,
        ExchangeColumn,
        InvoiceRefusal,
        earliestImportYear,
        homeAmountColumn;

import 'package:ledger_entries/model.dart' show maxDaysAhead;

import '../../../design_system/display/amount.dart' show groupDigits;
import '../formatting/words.dart';

/// Why a day of an imported file is not taken (D93).
String dayProblemWords(DayProblem problem) => switch (problem) {
  DayProblem.unreadable => '日期看不懂',
  DayProblem.shortYear => '年份只有兩位數，請寫成西元四位數（例如 2026）或民國三位數（例如 115）',
  DayProblem.tooEarly => '日期早於 $earliestImportYear 年',
  DayProblem.tooLate => '日期最多只能排到 $maxDaysAhead 天後',
};

/// Why an invoice of the ministry's file is left out.
String invoiceRefusalWords(InvoiceRefusal why) => switch (why) {
  InvoiceRefusal.rowsDisagree => '同一張發票的日期或商家前後不一致',
  InvoiceRefusal.tooEarly => dayProblemWords(DayProblem.tooEarly),
  InvoiceRefusal.unreadableDay => dayProblemWords(DayProblem.unreadable),
  InvoiceRefusal.shortYear => dayProblemWords(DayProblem.shortYear),
  InvoiceRefusal.tooLate => dayProblemWords(DayProblem.tooLate),
  InvoiceRefusal.badAmount => importAmountWords,
  InvoiceRefusal.voided => '已作廢',
  InvoiceRefusal.repeated => importAlreadyWords,
};

/// An amount of an imported line that is not one.
const importAmountWords = '金額看不懂';

/// An invoice of an imported file already recorded.
const importAlreadyWords = '已經記過';

/// A CSV whose first line lacks a column every file must have: the
/// required columns named ([ExchangeColumn.required]).
final importHeaderWords =
    '第一行要有${[for (final c in ExchangeColumn.values)
      if (c.required) '「${c.name}」'].join('和')}欄位';

/// A line of a CSV whose 編號 ([id]) an earlier line of the file has.
String importRepeatedIdWords(String id) =>
    '檔案裡已經有「${ExchangeColumn.id.name}」是 $id 的一筆';

/// A line of a CSV whose 當沖 cell says neither yes nor no.
final importDayTradeWords = '「${ExchangeColumn.dayTrade.name}」看不懂，請填「是」或留空';

/// A line of a CSV whose 標記 cell names no mark.
String importMarkWords(String words) =>
    '不認得的「${ExchangeColumn.mark.name}」「$words」';

/// A row of a foreign account with no rate to value it by and no worth
/// at home written: the file's own column is named.
const importMissingHomeWords =
    '還沒有匯率，請在「$homeAmountColumn」欄填${Words.homeWorth}的金額';

/// A refund's worth at home written not above zero (no [left]), or
/// larger than what of its purchase's worth is not yet given back
/// ([left]).
String refundHomeWords(int? left) => switch (left) {
  null => '「$homeAmountColumn」要大於 0',
  <= 0 => '原支出的「$homeAmountColumn」已經全部退完',
  _ => '「$homeAmountColumn」超過原支出還可退的 ${groupDigits(left)}',
};

/// A file chosen to import that cannot be read as text.
const importUnreadableFileWords = '讀不到這個檔案，請確認是 UTF-8 或 Big5 的文字檔';

/// What 匯入 says it reads, under its example: e-invoices.
const importInvoicesHint = '財政部「消費明細」的 CSV 或載具的 M／D 行都可以，記過的發票不會重複';

/// What 匯入 says it reads, under its example: a CSV.
const importCsvHint = '本 App 匯出的 CSV 可以完整匯回；沒有的帳戶與分類會自動新增';

/// What search finds in ImportExportSection (N8): each setting's name and the other
/// words a person may type for it, marking the card that section builds.
abstract final class ImportExportTopics {
  static const export = SettingTopic('匯出紀錄', words: ['匯出', 'CSV', 'Excel']);

  static const importCsv = SettingTopic('匯入 CSV', words: ['CSV', '匯入']);

  static const invoices = SettingTopic('電子發票', words: [Words.invoice, '載具']);
}
