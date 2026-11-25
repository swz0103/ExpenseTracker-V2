import 'package:ledger_loans/model/rate.dart';
import 'package:test/test.dart';

void main() {
  test('rates as typed, in hundredths of a percent', () {
    expect(rateOf('2.15'), 215);
    expect(rateOf(' 3 '), 300);
    expect(rateOf('abc'), isNull);
    expect(rateOf('120'), isNull);
    // Past two places, rounded half up from the digits as typed: through
    // a double, 1.005 came out as 100 and 0.285 as 28.
    expect(rateOf('1.005'), 101);
    expect(rateOf('0.285'), 29);
    expect(rateOf('2.674'), 267);
    expect(rateOf('.5'), 50);
    expect(rateOf('5.'), 500);
    expect(rateOf('100'), 10000);
    expect(rateOf('100.01'), isNull);
    expect(rateOf('-1'), isNull);
    expect(rateOf('.'), isNull);
    expect(rateOf(''), isNull);
  });

  test('D116: a rate typed below nothing keeps its sign, for the write '
      'rules to refuse', () {
    expect(signedRateOf('-2.15'), -215);
    expect(signedRateOf(' -1 '), -100);
    expect(signedRateOf('2.15'), 215);
    // -0 is no interest, not a rate below nothing.
    expect(signedRateOf('-0'), 0);
    expect(signedRateOf('-'), isNull);
    expect(signedRateOf('-abc'), isNull);
    expect(signedRateOf('--1'), isNull);
  });

  test('rates as shown', () {
    expect(rateText(215), '2.15');
    expect(rateText(205), '2.05');
    expect(rateText(210), '2.1');
    expect(rateText(300), '3');
    expect(rateText(null), '');
  });
}
