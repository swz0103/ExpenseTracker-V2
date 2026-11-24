import 'package:domain/data_exchange.dart'
    show DayProblem, InvoiceRefusal, earliestImportYear;

import '../../../design_system/display/amount.dart' show groupDigits;

/// Why a day of an imported file is not taken (D93).
String dayProblemWords(DayProblem problem) => switch (problem) {
  DayProblem.unreadable => '日期看不懂',
  DayProblem.shortYear => '年份只有兩位數，請寫成西元四位數（例如 2026）或民國三位數（例如 115）',
  DayProblem.tooEarly => '日期早於 $earliestImportYear 年',
};

/// Why an invoice of the ministry's file is left out.
String invoiceRefusalWords(InvoiceRefusal why) => switch (why) {
  InvoiceRefusal.rowsDisagree => '同一張發票的日期或商家前後不一致',
  InvoiceRefusal.tooEarly => dayProblemWords(DayProblem.tooEarly),
};

/// A row of a foreign account with no rate to value it by and no worth
/// at home written: the file's own column is named.
// Exception to glossary: the file format's column, kept so files written before read back.
const importMissingHomeWords = '還沒有匯率，請在「台幣金額」欄填折合新台幣的金額';

/// A refund's worth at home written not above zero (no [left]), or
/// larger than what of its purchase's worth is not yet given back
/// ([left]).
// Exception to glossary: the file format's column, kept so files written before read back.
String refundHomeWords(int? left) => switch (left) {
  null => '台幣金額要大於 0',
  <= 0 => '原支出的台幣金額已經全部退完',
  _ => '台幣金額超過原支出還可退的 ${groupDigits(left)}',
};
