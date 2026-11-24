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
}
