import 'package:expense_tracker/src/core/text/amounts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('an amount with the decimals its currency has is read exactly', () {
    expect(roundedMinorOf('1,200', 'TWD'), 1200);
    expect(roundedMinorOf('12.34', 'USD'), 1234);
    expect(roundedMinorOf('-12.3', 'USD'), -1230);
    expect(roundedMinorOf('7', 'USD'), 700);
    expect(roundedMinorOf('.5', 'USD'), 50);
  });

  test('more decimals round half away from zero, from the digits', () {
    // Through a double, 1.005 came out as 100.
    expect(roundedMinorOf('1.005', 'USD'), 101);
    expect(roundedMinorOf('-1.005', 'USD'), -101);
    expect(roundedMinorOf('1.004', 'USD'), 100);
    expect(roundedMinorOf('120.5', 'TWD'), 121);
    expect(roundedMinorOf('120.49', 'TWD'), 120);
  });

  test('what is not a number is not an amount', () {
    for (final text in ['', 'abc', '1.2.3', '--1', '.', '-']) {
      expect(roundedMinorOf(text, 'USD'), isNull, reason: text);
    }
  });
}
