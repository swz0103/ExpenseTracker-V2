import 'package:expense_tracker/src/core/ledger/models/models.dart';
import 'package:expense_tracker/src/core/ledger/repositories/holding_repository.dart';
import 'package:flutter_test/flutter_test.dart';

const _tsmc = Holding(
  '2330',
  '台積電',
  shares: 0,
  price: 1000,
  cost: 0,
  change: 0,
);

Entry _trade(String id, EntryType type, int day, int shares, int amount) =>
    Entry(
      id: id,
      date: DateTime.utc(2026, 9, day),
      type: type,
      amount: amount,
      account: 'bank',
      holding: '2330',
      shares: shares,
    );

/// The day the holdings are read on: after every trade below but those
/// an old book dated later.
final _today = DateTime.utc(2026, 9, 10);

void main() {
  final buy = _trade('buy', EntryType.buy, 1, 10, 9000);
  final sell = _trade('sell', EntryType.sell, 3, 4, 4400);

  group('trades an old book dated after today (D70)', () {
    final later = _trade('later', EntryType.buy, 20, 5, 5000);

    test('one joins the holdings on its day, not before', () {
      final holdings = HoldingRepository([_tsmc], moveOf: (_) => null)
        ..replay([buy, sell, later], today: _today);
      // On 9/10: 10 − 4 = 6; the purchase of 9/20 is 預定.
      expect(holdings.byCode('2330')?.shares, 6);
      holdings.replay([buy, sell, later], today: DateTime.utc(2026, 9, 20));
      // On 9/20: 6 + 5 = 11.
      expect(holdings.byCode('2330')?.shares, 11);
    });

    test('a book whose later sale would be short is still refused', () {
      final holdings = HoldingRepository([_tsmc], moveOf: (_) => null)
        ..replay([buy, sell], today: _today);
      // A sale of 7 on 9/25: 10 − 4 − 7 = −1, short though not yet due.
      final short = _trade('short', EntryType.sell, 25, 7, 7700);
      expect(
        () => holdings.replay([buy, sell, short], today: _today),
        throwsStateError,
      );
      expect(holdings.byCode('2330')?.shares, 6);
      // Lenient, as for a book just read, it is left out and nothing
      // throws.
      holdings.replay([buy, sell, short], today: _today, lenient: true);
      expect(holdings.byCode('2330')?.shares, 6);
    });
  });

  HoldingRepository make({Map<String, double> moves = const {}}) =>
      HoldingRepository([_tsmc], moveOf: (code) => moves[code])
        ..replay([buy, sell], today: _today);

  test('holdings are read only after a replay', () {
    final holdings = HoldingRepository([_tsmc], moveOf: (_) => null);
    expect(() => holdings.all, throwsStateError);
    holdings.replay(const [], today: _today);
    // A stock quoted but not held is not one of the holdings.
    expect(holdings.all, isEmpty);
    expect(holdings.hasQuote('2330'), isTrue);
  });

  test('the trades are replayed over the starting positions', () {
    final holdings = make();
    expect(holdings.byCode('2330')?.shares, 6);
    expect(holdings.byCode('0050'), isNull);
    expect(holdings.sharesOn('2330', DateTime.utc(2026, 9, 2)), 10);
    expect(holdings.sharesOn('2330', DateTime.utc(2026, 9, 3)), 6);
    expect(holdings.lotsOf('2330').fold(0, (n, l) => n + l.shares), 6);
  });

  test('a stock sold to the last share is sold out, not held', () {
    final holdings = HoldingRepository([_tsmc], moveOf: (_) => null)
      // 10 bought, 4 then 6 sold: 0 left, with a realised gain.
      ..replay([
        buy,
        sell,
        _trade('rest', EntryType.sell, 5, 6, 6600),
      ], today: _today);
    expect(holdings.all.map((h) => h.code), ['2330']);
    expect(holdings.held, isEmpty);
    expect(holdings.soldOut.map((h) => h.code), ['2330']);
    expect(make().held.map((h) => h.code), ['2330']);
    expect(make().soldOut, isEmpty);
  });

  test('a stock sold out with nothing gained is still found to value '
      'the days it was held (D105)', () {
    final holdings = HoldingRepository([_tsmc], moveOf: (_) => null)
      // 10 bought at 900, all sold at 900 again: nothing realised (the
      // sale's 9000 less the lot's 9000), so the holdings list it not.
      ..replay([
        buy,
        _trade('all', EntryType.sell, 5, 10, 9000),
      ], today: _today);
    expect(holdings.all, isEmpty);
    expect(holdings.everByCode('2330')?.price, 1000);
    expect(holdings.everByCode('0050'), isNull);
    // No split since: a day's count is today's.
    expect(holdings.inTodaysShares('2330', DateTime.utc(2026, 9, 2), 10), 10);
  });

  test("the day's change follows the shares held", () {
    final holdings = make(moves: {'2330': 2.5});
    expect(holdings.byCode('2330')?.change, 15);
  });

  test('shares bought after the quote day are not in its change (F25)', () {
    // The close is Friday 9/4's; 10 more shares are bought Monday 9/7.
    final monday = _trade('monday', EntryType.buy, 7, 10, 10000);
    final holdings = HoldingRepository(
      [_tsmc],
      moveOf: (_) => 2.5,
      quoteDayOf: (_) => DateTime.utc(2026, 9, 4),
    )..replay([buy, sell, monday], today: _today);
    expect(holdings.byCode('2330')?.shares, 16);
    // 6 shares held at the end of 9/4 × 2.5 = 15, not 16 × 2.5 = 40.
    expect(holdings.byCode('2330')?.change, 15);
    expect(holdings.dayChange, 15);
  });

  test('a stock with a fetched close has a quote; another does not', () {
    final holdings = make();
    expect(holdings.hasQuote('2330'), isTrue);
    expect(holdings.hasQuote('0050'), isFalse);
  });

  test('an oversold replay throws and leaves the holdings as they were', () {
    final holdings = make();
    final oversold = _trade('more', EntryType.sell, 4, 7, 7700);
    expect(
      () => holdings.replay([buy, sell, oversold], today: _today),
      throwsStateError,
    );
    expect(holdings.byCode('2330')?.shares, 6);
  });

  test('a lenient replay leaves the oversold trade out', () {
    final holdings = make();
    final oversold = _trade('more', EntryType.sell, 4, 7, 7700);
    holdings.replay([buy, sell, oversold], today: _today, lenient: true);
    expect(holdings.byCode('2330')?.shares, 6);
  });

  test('whether a book of trades holds is told without changing anything', () {
    final holdings = make();
    expect(holdings.holdsWith([buy, sell]), isTrue);
    expect(holdings.holdsWith([sell]), isFalse);
    expect(holdings.byCode('2330')?.shares, 6);
  });

  test('a list never changed is answered once, again once the book is '
      'read anew or the starting positions change (FIX-R34)', () {
    final kept = List<Entry>.unmodifiable([sell]);
    final holdings = HoldingRepository(const [], moveOf: (_) => null)
      ..replay(const [], today: _today);
    // 4 sold of none held.
    expect(holdings.holdsWithKept(kept), isFalse);
    expect(holdings.holdsWithKept(kept), isFalse);
    // Read as an old book's, the short sale is left out and kept so.
    holdings.replay(kept, today: _today, lenient: true);
    expect(holdings.holdsWithKept(kept), isTrue);
    final fresh = HoldingRepository(const [], moveOf: (_) => null)
      ..replay(const [], today: _today);
    expect(fresh.holdsWithKept(kept), isFalse);
    // 10 held from the start: 4 sold of them hold.
    fresh.replaceStart([
      const Holding(
        '2330',
        '台積電',
        shares: 10,
        price: 1000,
        cost: 9000,
        change: 0,
      ),
    ]);
    expect(fresh.holdsWithKept(kept), isTrue);
  });

  test('a list handed out stays as it was after another replay', () {
    final holdings = make();
    final before = holdings.all;
    holdings.replay([buy], today: _today);
    expect(before.single.shares, 6);
    expect(holdings.all.single.shares, 10);
    expect(() => holdings.all.add(_tsmc), throwsUnsupportedError);
  });

  test('new starting positions count after the next replay', () {
    final holdings = make();
    holdings.replaceStart([_tsmc.copyWith(shares: 5, cost: 4000)]);
    expect(holdings.start.single.shares, 5);
    holdings.replay([buy, sell], today: _today);
    expect(holdings.byCode('2330')?.shares, 11);
  });
}
