import 'package:kernel/kernel.dart';
import 'package:ledger_postings/model/intents.dart';
import 'package:test/test.dart';

import '../support/book.dart';

void main() {
  test('each kind has its own name; openings stand before every record', () {
    final kinds = {
      OpeningBalance.kind,
      Spending.kind,
      Earning.kind,
      Transfer.kind,
      OpeningPosition.kind,
      Buy.kind,
      Sell.kind,
      Dividend.kind,
      OutOfHoldings.kind,
    };
    expect(kinds.length, 9);
    final o = OpeningBalance(
      id: const IntentId('o'),
      seq: 0,
      account: bank,
      amount: 1,
    );
    expect((o.date, o.type), (Day.beforeAll, OpeningBalance.kind));
    final p = OpeningPosition(
      id: const IntentId('p'),
      seq: 0,
      code: 'x',
      shares: 1,
      cost: 1,
    );
    expect(
      (p.date, p.realised, p.dividends, p.type),
      (Day.beforeAll, 0, 0, OpeningPosition.kind),
    );
  });

  test('a reduction is a dividend taking shares back', () {
    Dividend d(int shares) => Dividend(
      id: const IntentId('d'),
      date: day(1, 1),
      seq: 1,
      cash: bank,
      code: 'x',
      gross: 1,
      shares: shares,
    );
    expect(d(-1).isReduction, isTrue);
    expect(d(1).isReduction, isFalse);
    expect(
      (d(1).fee, d(1).tax, d(1).split, d(1).type),
      (0, 0, false, Dividend.kind),
    );
    final s = Sell(
      id: const IntentId('s'),
      date: day(1, 1),
      seq: 1,
      cash: bank,
      code: 'x',
      gross: 1,
      shares: 1,
    );
    expect((s.average, s.type, s.fee, s.tax), (false, Sell.kind, 0, 0));
    final b = Buy(
      id: const IntentId('b'),
      date: day(1, 1),
      seq: 1,
      cash: bank,
      code: 'x',
      gross: 1,
      shares: 1,
    );
    expect(b.type, Buy.kind);
  });

  test('foreign values say what they hold', () {
    expect(const Worth(5).amount, 5);
    expect(const ReceivedFeeSameNumber(7).received, 7);
    expect(const SameNumber(), isA<ForeignValue>());
    final t = Transfer(
      id: const IntentId('t'),
      date: day(1, 1),
      seq: 1,
      from: bank,
      to: card,
      amount: 1,
    );
    expect((t.fee, t.feeCategory, t.type), (0, null, Transfer.kind));
    final o = OutOfHoldings(
      id: const IntentId('o'),
      date: day(1, 1),
      seq: 1,
      cash: bank,
      settlement: 1,
      reason: OutOfHoldingsReason.noStock,
    );
    expect(
      (o.type, o.reason),
      (OutOfHoldings.kind, OutOfHoldingsReason.noStock),
    );
  });
}
