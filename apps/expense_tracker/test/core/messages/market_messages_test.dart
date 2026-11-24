import 'package:expense_tracker/src/core/messages/market_messages.dart';
import 'package:flutter_test/flutter_test.dart';

/// What a refresh of closes and rates says of what it did not take.
void main() {
  test('nothing to say when all was taken', () {
    expect(marketProblem(missed: const [], doubted: const []), isNull);
  });

  test('stocks with no close are named', () {
    expect(
      marketProblem(missed: const ['9999', '1234'], doubted: const []),
      '9999、1234 抓不到收盤價',
    );
  });

  test('figures doubted are named, the ones before kept (D95)', () {
    expect(
      marketProblem(missed: const [], doubted: const ['2330', 'USD']),
      '2330、USD 的行情與前次相差太大，先沿用前次的數字',
    );
    expect(
      marketProblem(missed: const ['9999'], doubted: const ['2330']),
      '9999 抓不到收盤價；2330 的行情與前次相差太大，先沿用前次的數字',
    );
  });
}
