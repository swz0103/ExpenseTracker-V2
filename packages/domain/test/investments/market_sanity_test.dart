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

  group('D101: a doubted move is taken when there is reason to', () {
    test('a split of one for twenty the book holds is taken at once', () {
      // 1,000 to 50 is twenty times smaller: doubted alone.
      expect(takesFetched(kept: 1000, fetched: 50), isFalse);
      expect(
        takesFetched(kept: 1000, fetched: 50, reshapedSince: true),
        isTrue,
      );
    });

    test('a split of one for ten then a 5% fall: taken the second time', () {
      // 1,000 / 10 = 100, less 5% = 95: 1,000 / 95 = 10.5 times, doubted.
      expect(takesFetched(kept: 1000, fetched: 95), isFalse);
      // Fetched again at 96: |96 - 95| = 1 <= 95 x 0.1 = 9.5, agreed.
      expect(takesFetched(kept: 1000, fetched: 96, doubtedBefore: 95), isTrue);
      // The same close fetched again agrees too.
      expect(takesFetched(kept: 1000, fetched: 95, doubtedBefore: 95), isTrue);
    });

    test('after a long gap the kept figure gives way', () {
      expect(doubtfulMoveKeptDays, 30);
      expect(takesFetched(kept: 1000, fetched: 20, keptDaysAgo: 30), isFalse);
      expect(takesFetched(kept: 1000, fetched: 20, keptDaysAgo: 31), isTrue);
    });

    test('a garbled figure is still refused', () {
      // 1,000 written two places too long: 100,000, once.
      expect(takesFetched(kept: 1000, fetched: 100000), isFalse);
      // Then the true close, near the kept one: taken as ever.
      expect(
        takesFetched(kept: 1000, fetched: 1010, doubtedBefore: 100000),
        isTrue,
      );
      // Two garbled figures that disagree: 100,000 then 1,000,000 is
      // |1,000,000 - 100,000| = 900,000 > 100,000 x 0.1 = 10,000.
      expect(agreeingFetchesBand, 0.1);
      expect(
        takesFetched(kept: 1000, fetched: 1000000, doubtedBefore: 100000),
        isFalse,
      );
      // No price is taken whatever the reason.
      expect(
        takesFetched(
          kept: 1000,
          fetched: double.nan,
          keptDaysAgo: 99,
          reshapedSince: true,
        ),
        isFalse,
      );
      expect(
        takesFetched(kept: 1000, fetched: 20, doubtedBefore: double.nan),
        isFalse,
      );
    });
  });
}
