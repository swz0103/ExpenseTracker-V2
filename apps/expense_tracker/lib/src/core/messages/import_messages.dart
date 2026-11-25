import 'package:domain/data_exchange.dart'
    show DayProblem, InvoiceRefusal, earliestImportYear, homeAmountColumn;

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
};

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

/// What 匯入 says it reads, under its example: e-invoices.
const importInvoicesHint = '財政部「消費明細」的 CSV 或載具的 M／D 行都可以，記過的發票不會重複';

/// What 匯入 says it reads, under its example: a CSV.
const importCsvHint = '本 App 匯出的 CSV 可以完整匯回；沒有的帳戶與分類會自動新增';
