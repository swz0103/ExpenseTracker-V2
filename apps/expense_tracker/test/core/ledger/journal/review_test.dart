import 'dart:io';

import 'package:expense_tracker/src/core/ledger/journal/old_shapes.dart';
import 'package:expense_tracker/src/core/ledger/journal/review.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../scenarios/ledger/journal/awkward_book.dart';

void main() {
  late Directory scratch;
  setUp(() => scratch = Directory.systemTemp.createTempSync('review-'));
  tearDown(() => scratch.deleteSync(recursive: true));

  test('each record in an old shape is listed once, with its reason, in '
      'the order kept; its figures left as they are', () async {
    final ledger = await openKept(scratch);
    final before = ledger.balanceService.balance('usd');
    expect(ledger.recordsNeedingReview(), const [
      NoWorthAtHome('usd-bare'),
      NothingReceived('jpy-bare'),
      IncomeUnderSpending('under-food'),
      SpendingUnderIncome('under-pay'),
      ForeignFee('usd-fee'),
      Oversold('oversold'),
      NoStock('no-stock'),
      ForeignTrade('usd-div'),
      NoSuchAccount('gone'),
      InstalmentsOffCard('bank-instal'),
    ]);
    expect(ledger.balanceService.balance('usd'), before);
  });

  test('one reason for each old shape, and none in a sound book', () {
    expect({
      for (final r in const <NeedsReview>[
        NoWorthAtHome('a'),
        NothingReceived('a'),
        IncomeUnderSpending('a'),
        SpendingUnderIncome('a'),
        ForeignFee('a'),
        Oversold('a'),
        NoStock('a'),
        ForeignTrade('a'),
        NoSuchAccount('a'),
        InstalmentsOffCard('a'),
      ])
        r.shape,
    }, OldShape.values.toSet());
    expect('${const Oversold('s')}', 'oversoldTrade(s)');
    expect(const Oversold('s'), isNot(const NoStock('s')));
    final sound = Ledger(
      today: day(10, 4),
      accounts: awkwardAccounts,
      categories: awkwardCategories(),
      entries: fitting,
      holdings: const [],
      budgets: const [],
      recurring: const [],
    );
    expect(sound.recordsNeedingReview(), isEmpty);
  });
}
