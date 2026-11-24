import 'dart:io';

import 'package:expense_tracker/src/core/ledger/journal/review.dart'
    show Oversold;
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/ledger/portfolio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'awkward_book.dart';

/// A book an older version kept with a sale of more shares than were held
/// (`oversold`, left out as it is read, D47): a change beside it is held
/// only to what it makes short itself. A valid trade is kept; a short one
/// is refused as the write rules refuse it ([RecordRefused]), never with
/// the old sale's [OversoldTrade].
void main() {
  late Directory scratch;
  setUp(() => scratch = Directory.systemTemp.createTempSync('oversold-'));
  tearDown(() => scratch.deleteSync(recursive: true));

  test('a valid trade beside an old oversold sale is kept', () async {
    final ledger = await openKept(scratch);
    expect(ledger.recordsNeedingReview().whereType<Oversold>(), isNotEmpty);
    final held = ledger.holdings.byCode('2330')!.shares;
    ledger.entryCommands.add(
      Entry(
        id: 'more',
        date: day(10, 3),
        type: EntryType.buy,
        amount: 1000,
        account: 'bank',
        holding: '2330',
        shares: 2,
      ),
    );
    expect(ledger.holdings.byCode('2330')!.shares, held + 2);
    ledger.entryCommands.add(
      Entry(
        id: 'less',
        date: day(10, 3),
        type: EntryType.sell,
        amount: 500,
        account: 'bank',
        holding: '2330',
        shares: 1,
      ),
    );
    expect(ledger.holdings.byCode('2330')!.shares, held + 1);
    // The old sale stays in the book, left out of the holdings as read.
    expect(ledger.entries.byId('oversold'), isNotNull);
  });

  test('a short trade beside it is refused as the rules refuse it, the book '
      'as it was', () async {
    final ledger = await openKept(scratch);
    final held = ledger.holdings.byCode('2330')!.shares;
    final count = ledger.entries.all.length;
    Object? thrown;
    try {
      ledger.entryCommands.add(
        Entry(
          id: 'short',
          date: day(10, 3),
          type: EntryType.sell,
          amount: 500,
          account: 'bank',
          holding: '2330',
          shares: held + 1,
        ),
      );
    } on Object catch (error) {
      thrown = error;
    }
    expect(thrown, isA<RecordRefused>());
    expect(thrown, isNot(isA<OversoldTrade>()));
    expect(ledger.entries.all.length, count);
    expect(ledger.holdings.byCode('2330')!.shares, held);
  });
}
