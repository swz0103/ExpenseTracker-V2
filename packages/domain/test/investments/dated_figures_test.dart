import 'package:core/time/calendar_day.dart';
import 'package:domain/investments.dart';
import 'package:test/test.dart';

/// D58: a rate or close for a day is that day's, else the nearest earlier
/// day's, else today's.
void main() {
  BusinessDate d(int m, int day) => BusinessDate(2026, m, day);

  // Rates kept on scattered days: 3/2, 3/9 and 4/1.
  final usd = DatedFigures({
    'USD': {d(4, 1): 32.4, d(3, 2): 31.5, d(3, 9): 31.9},
  });

  test('the day itself', () {
    expect(usd.on('USD', d(3, 9)), (
      figure: 31.9,
      of: d(3, 9),
      found: FoundOn.theDay,
    ));
    expect(usd.exactly('USD', d(3, 2)), 31.5);
    expect(usd.latestOf('USD'), d(4, 1));
    expect(usd.latestOf('JPY'), isNull);
  });

  test('else the nearest earlier day', () {
    // 3/15 lies between 3/9 and 4/1: 3/9's.
    expect(usd.on('USD', d(3, 15)), (
      figure: 31.9,
      of: d(3, 9),
      found: FoundOn.earlierDay,
    ));
    // After the last day kept: that one's.
    expect(usd.on('USD', d(5, 1))?.figure, 32.4);
    expect(usd.exactly('USD', d(3, 15)), isNull);
  });

  test('else today\'s, given or the latest kept', () {
    expect(usd.on('USD', d(1, 5), today: 33.0, todayOf: d(4, 2)), (
      figure: 33.0,
      of: d(4, 2),
      found: FoundOn.today,
    ));
    expect(usd.on('USD', d(1, 5)), (
      figure: 32.4,
      of: d(4, 1),
      found: FoundOn.today,
    ));
    // A currency with no day kept: only today's.
    expect(usd.on('JPY', d(3, 9), today: 0.21), (
      figure: 0.21,
      of: null,
      found: FoundOn.today,
    ));
    expect(usd.on('JPY', d(3, 9)), isNull);
    expect(usd.exactly('JPY', d(3, 9)), isNull);
  });

  test('a figure kept for a day replaces that day\'s only', () {
    final more = usd
        .withFigure('USD', d(3, 9), 32.0)
        .withFigure('JPY', d(3, 9), 0.2);
    expect(more.exactly('USD', d(3, 9)), 32.0);
    expect(more.exactly('USD', d(3, 2)), 31.5);
    expect(more.exactly('JPY', d(3, 9)), 0.2);
    expect(more.figures['USD']!.length, 3);
    // The first is unchanged.
    expect(usd.exactly('USD', d(3, 9)), 31.9);
  });

  test('days across years are in order', () {
    final f = DatedFigures({
      'X': {BusinessDate(2025, 12, 31): 1, BusinessDate(2026, 1, 1): 2},
    });
    expect(f.on('X', BusinessDate(2025, 12, 31))?.figure, 1);
    expect(f.on('X', BusinessDate(2026, 6, 1))?.figure, 2);
  });

  test('empty', () {
    expect(DatedFigures().isEmpty, isTrue);
    expect(DatedFigures({'X': {}}).isEmpty, isTrue);
    expect(MarketHistory().isEmpty, isTrue);
    expect(MarketHistory(closes: usd).isEmpty, isFalse);
  });
}
