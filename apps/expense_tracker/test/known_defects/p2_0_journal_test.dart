// The old shapes the journal of postings makes visible (work package
// 2.0): each is posted today in a recorded form that keeps every figure
// as the app shows it. Decision D47: the app changes none of them; it
// lists them (Ledger.recordsNeedingReview) for the person to put right
// by hand, on a screen not yet built. Each test states what is true
// once that is done: the kept book of awkward shapes posts with none of
// that shape left.
import 'dart:io';

import 'package:expense_tracker/src/core/ledger/journal/old_shapes.dart';
import 'package:flutter_test/flutter_test.dart';

import '../core/ledger/journal/posted_book.dart';
import '../scenarios/ledger/journal/awkward_book.dart' show openKept;
import 'known_defect.dart';

void main() {
  late Directory scratch;
  setUp(() => scratch = Directory.systemTemp.createTempSync('jrn-'));
  tearDown(() => scratch.deleteSync(recursive: true));

  Future<int> left(OldShape shape) async {
    final parity = await parityOf(await openKept(scratch));
    return parity.shapes[shape] ?? 0;
  }

  test(
    'JRN-01: foreign spending or income has a worth at home',
    () async => expect(await left(OldShape.foreignWithoutHome), 0),
    skip: knownDefect('JRN-01', '待決定'),
  );
  test(
    'JRN-02: a transfer across currencies says what arrived',
    () async => expect(await left(OldShape.crossCurrencyWithoutReceived), 0),
    skip: knownDefect('JRN-02', '待決定'),
  );
  test(
    'JRN-03: income is not kept under a spending category',
    () async => expect(await left(OldShape.incomeUnderSpendingCategory), 0),
    skip: knownDefect('JRN-03', '待決定'),
  );
  test(
    'JRN-04: spending is not kept under an income category',
    () async => expect(await left(OldShape.spendingUnderIncomeCategory), 0),
    skip: knownDefect('JRN-04', '待決定'),
  );
  test(
    'JRN-05: a fee paid in a foreign currency has a worth at home',
    () async => expect(await left(OldShape.foreignTransferFee), 0),
    skip: knownDefect('JRN-05', '待決定'),
  );
  test(
    'JRN-06: no trade takes more shares than are held',
    () async => expect(await left(OldShape.oversoldTrade), 0),
    skip: knownDefect('JRN-06', '待決定'),
  );
  test(
    'JRN-07: every trade names its stock',
    () async => expect(await left(OldShape.tradeWithoutStock), 0),
    skip: knownDefect('JRN-07', '待決定'),
  );
  test(
    'JRN-08: no trade is paid from or into a foreign account',
    () async => expect(await left(OldShape.foreignTrade), 0),
    skip: knownDefect('JRN-08', '待決定'),
  );
  test(
    'JRN-09: every record names an account the book keeps',
    () async => expect(await left(OldShape.missingAccount), 0),
    skip: knownDefect('JRN-09', '待決定'),
  );
  test(
    'JRN-10: purchases in instalments are on cards',
    () async => expect(await left(OldShape.instalmentsOffCard), 0),
    skip: knownDefect('JRN-10', '待決定'),
  );
}
