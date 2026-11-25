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
    // -0.01% is -1 hundredth: below nothing by the least step.
    expect(rateOf('-0.01'), isNull);
    expect(rateOf('.'), isNull);
    expect(rateOf(''), isNull);
  });

  test('D116: a rate typed below nothing keeps its sign, for the write '
      'rules to refuse', () {
    expect(readRate('-2.15'), isA<RateRead>().having(_hundredths, '', -215));
    expect(readRate(' -1 '), isA<RateRead>().having(_hundredths, '', -100));
    expect(readRate('2.15'), isA<RateRead>().having(_hundredths, '', 215));
    // -0 is no interest, not a rate below nothing.
    expect(readRate('-0'), isA<RateRead>().having(_hundredths, '', 0));
    expect(readRate('-'), isA<RateUnreadable>());
    expect(readRate('-abc'), isA<RateUnreadable>());
    expect(readRate('--1'), isA<RateUnreadable>());
  });

  test('D118: text that is no number reads as unreadable, not as no rate', () {
    expect(readRate('abc'), isA<RateUnreadable>());
    expect(readRate('2,5'), isA<RateUnreadable>());
    expect(readRate('2%'), isA<RateUnreadable>());
    expect(readRate('.'), isA<RateUnreadable>());
    expect(readRate(''), isA<RateUnreadable>());
    expect(readRate('   '), isA<RateUnreadable>());
  });

  test('D118: a rate above 100% is read as typed, for the write rules to '
      'refuse; rateOf keeps none of it', () {
    expect(maxLoanRate, 10000); // 100% in hundredths of a percent
    expect(readRate('100.01'), isA<RateRead>().having(_hundredths, '', 10001));
    expect(readRate('120'), isA<RateRead>().having(_hundredths, '', 12000));
    // 1,000% is 100000 hundredths; 999,999% is 99999900, under the cap.
    expect(readRate('1000'), isA<RateRead>().having(_hundredths, '', 100000));
    expect(
      readRate('999999'),
      isA<RateRead>().having(_hundredths, '', 99999900),
    );
    expect(rateOf('100.01'), isNull);
    // Past a million percent it reads as a million: 1,000,000 x 100.
    expect(
      readRate('99999999999999999999999'),
      isA<RateRead>().having(_hundredths, '', 100000000),
    );
    // 2,000,000.5% is capped at 1,000,000 whole: 100000000 + 50.
    expect(
      readRate('2000000.5'),
      isA<RateRead>().having(_hundredths, '', 100000050),
    );
    // 0001.5 is 1.5%: 150.
    expect(readRate('0001.5'), isA<RateRead>().having(_hundredths, '', 150));
    // A long run of digits used to read as 0%: int.tryParse gave up on it.
    expect(rateOf('99999999999999999999999'), isNull);
  });

  test('rates as shown', () {
    expect(rateText(215), '2.15');
    expect(rateText(205), '2.05');
    expect(rateText(210), '2.1');
    expect(rateText(300), '3');
    expect(rateText(null), '');
  });
}

int _hundredths(RateRead read) => read.hundredths;
