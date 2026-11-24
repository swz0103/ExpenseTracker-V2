import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/ledger/portfolio.dart';
import 'package:flutter_test/flutter_test.dart';

/// R12 F2: replayed leniently, as a book just read is, a trade the
/// holdings cannot work in is left out and named, never thrown.
void main() {
  Entry trade(String id, EntryType type, int shares, {int day = 1}) => Entry(
    id: id,
    date: DateTime.utc(2026, 9, day),
    type: type,
    amount: 6000,
    account: 'bank',
    category: '',
    holding: '2330',
    shares: shares,
  );

  final entries = [
    trade('buy', EntryType.buy, 10),
    trade('minus', EntryType.sell, -5, day: 2),
  ];

  test('a sale of fewer than no shares is left out as faulty', () {
    final read = Portfolio.replay(const [], entries, lenient: true);
    expect(read.faulty.keys, ['minus']);
    expect(read.faulty['minus'], isA<ArgumentError>());
    expect(read.leftOut, isEmpty);
    expect(read.holdings.single.shares, 10);
  });

  test('replayed strictly, it is thrown as before', () {
    expect(
      () => Portfolio.replay(const [], entries),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('a count kept on a day is scaled by the splits after it (D105)', () {
    final p = Portfolio.replay(const [], [
      trade('buy', EntryType.buy, 1000),
      Entry(
        id: 'split',
        date: DateTime.utc(2026, 9, 10),
        type: EntryType.dividend,
        amount: 0,
        account: 'bank',
        category: '',
        holding: '2330',
        shares: 19000,
        split: true,
      ),
    ]);
    // 1:20: 1000 held on Sep 5 are 1000 x 20000 / 1000 = 20000 today.
    expect(p.inTodaysShares('2330', DateTime.utc(2026, 9, 5), 1000), 20000);
    // On the split's own day the count is already today's.
    expect(p.inTodaysShares('2330', DateTime.utc(2026, 9, 10), 20000), 20000);
    expect(p.sharesOn('2330', DateTime.utc(2026, 9, 5)), 20000);
    // D101: a close kept before the split may be far from the next.
    // 1:20, shares 1,000 to 20,000: multiplied by 20,000 / 1,000 = 20.
    expect(p.reshapedBy('2330', DateTime.utc(2026, 9, 9)), 20);
    expect(p.reshapedBy('2330', DateTime.utc(2026, 9, 10)), isNull);
    expect(p.reshapedBy('2330', null), 20);
    expect(p.reshapedBy('0050', null), isNull);
  });

  test('a reshape that leaves no share counts as once; the later ones '
      'still count (review 25)', () {
    Entry reshape(String id, int shares, int day) => Entry(
      id: id,
      date: DateTime.utc(2026, 9, day),
      type: EntryType.dividend,
      amount: 0,
      account: 'bank',
      category: '',
      holding: '2330',
      shares: shares,
      split: shares > 0,
    );
    final p = Portfolio.replay(const [], [
      trade('buy', EntryType.buy, 5),
      // A reduction that takes all 5: 5 to 0, counted as once.
      reshape('cut', -5, 10),
      trade('again', EntryType.buy, 1000, day: 11),
      // 1:2, 1,000 to 2,000: x 2.
      reshape('split', 1000, 12),
    ]);
    // 1 (the cut) x 2000 / 1000 = 2, not 0 x 2 = 0.
    expect(p.reshapedBy('2330', DateTime.utc(2026, 9, 9)), 2);
  });
}
