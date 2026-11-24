import 'package:domain/investments.dart';
import 'package:test/test.dart';

/// D95: a close or rate more than ten times away from the last one kept
/// is doubted.
void main() {
  test('within ten times either way is taken', () {
    expect(doubtfulMoveFactor, 10);
    // 1,000 × 10 = 10,000 and 1,000 ÷ 10 = 100: the edges are taken.
    expect(doubtfulMove(kept: 1000, fetched: 10000), isFalse);
    expect(doubtfulMove(kept: 1000, fetched: 100), isFalse);
    // A split of one for four: 200 to 50.
    expect(doubtfulMove(kept: 200, fetched: 50), isFalse);
    expect(doubtfulMove(kept: 31.5, fetched: 32.1), isFalse);
  });

  test('further away is doubted', () {
    expect(doubtfulMove(kept: 1000, fetched: 10000.5), isTrue);
    expect(doubtfulMove(kept: 1000, fetched: 99.9), isTrue);
    // A rate of 99,999,999,999 or 0.00001 against 31.5.
    expect(doubtfulMove(kept: 31.5, fetched: 99999999999), isTrue);
    expect(doubtfulMove(kept: 31.5, fetched: 0.00001), isTrue);
  });

  test('a figure that is no price is doubted, kept or not', () {
    for (final fetched in [0.0, -5.0, double.nan, double.infinity]) {
      expect(doubtfulMove(kept: 10, fetched: fetched), isTrue);
      expect(doubtfulMove(kept: null, fetched: fetched), isTrue);
    }
  });

  test('with nothing sound kept, a positive figure is taken', () {
    expect(doubtfulMove(kept: null, fetched: 99999), isFalse);
    expect(doubtfulMove(kept: 0, fetched: 5), isFalse);
    expect(doubtfulMove(kept: double.nan, fetched: 5), isFalse);
  });
}
