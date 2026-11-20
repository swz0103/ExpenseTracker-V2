import 'package:expense_tracker/src/features/investments/model/dividend_outlook.dart';
import 'package:expense_tracker/src/features/investments/model/returns.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  DividendGuess guess(String code, int month, int amount, {int year = 2027}) =>
      (
        code: code,
        name: '名$code',
        month: DateTime.utc(year, month),
        amount: amount,
      );

  test('the twelve months after today, each holding summed in its month', () {
    final outlook = DividendOutlook.of([
      guess('2330', 1, 500),
      guess('2330', 1, 300),
      guess('0056', 1, 200),
      guess('0056', 4, 1000),
      // Beyond the twelve months: left out.
      guess('0056', 1, 999, year: 2028),
    ], DateTime.utc(2026, 12, 15));
    expect(outlook.months.first, DateTime.utc(2027));
    expect(outlook.months.last, DateTime.utc(2027, 12));
    expect(outlook.byMonth[0], {'2330': 800, '0056': 200});
    expect(outlook.byMonth[3], {'0056': 1000});
    expect(outlook.sums[0], 1000);
    expect(outlook.total, 2000);
    expect(outlook.order, ['0056', '2330']);
    expect(outlook.first, 0);
    expect(outlook.names['2330'], '名2330');
  });

  test('none expected: no first month, nothing in all', () {
    final outlook = DividendOutlook.of(const [], DateTime.utc(2026, 10, 4));
    expect(outlook.first, -1);
    expect(outlook.total, 0);
    expect(outlook.order, isEmpty);
  });
}
