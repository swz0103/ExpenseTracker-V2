import 'package:domain/data_exchange.dart';
import 'package:expense_tracker/src/core/messages/import_messages.dart';
import 'package:flutter_test/flutter_test.dart';

/// D93 and R12 F6: why a day or an invoice of a file is not taken.
void main() {
  test('each reason a day is refused has its words', () {
    expect(dayProblemWords(DayProblem.unreadable), '日期看不懂');
    expect(
      dayProblemWords(DayProblem.shortYear),
      '年份只有兩位數，請寫成西元四位數（例如 2026）或民國三位數（例如 115）',
    );
    expect(dayProblemWords(DayProblem.tooEarly), '日期早於 1950 年');
  });

  test('each reason an invoice is left out has its words', () {
    expect(
      invoiceRefusalWords(InvoiceRefusal.rowsDisagree),
      '同一張發票的日期或商家前後不一致',
    );
    expect(invoiceRefusalWords(InvoiceRefusal.tooEarly), '日期早於 1950 年');
  });
}
