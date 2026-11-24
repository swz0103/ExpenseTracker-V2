import 'package:domain/data_exchange.dart'
    show DayProblem, InvoiceRefusal, earliestImportYear;

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
