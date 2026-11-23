import 'package:ledger_postings/model/intents.dart';
import 'package:ledger_postings/model/vocabulary.dart';
import 'package:ledger_postings/rules/registry.dart';
import 'package:test/test.dart';

void main() {
  test('every kind is registered once; instalments amend before the '
      'foreign value', () {
    final r = todaysIntents(scheduleOf: (_) => null);
    expect(r.types.toSet(), {
      OpeningBalance.kind,
      Spending.kind,
      Earning.kind,
      Transfer.kind,
      OpeningPosition.kind,
      Buy.kind,
      Sell.kind,
      Dividend.kind,
      OutOfHoldings.kind,
    });
    expect([for (final a in r.amenders) a.slot], [Slots.instalments, Slots.fx]);
    expect(
      [
        for (final t in r.types)
          if (r[t]!.amendable) t.value,
      ],
      [
        Spending.kind.value,
        Earning.kind.value,
        Transfer.kind.value,
        Buy.kind.value,
        Sell.kind.value,
        Dividend.kind.value,
        OutOfHoldings.kind.value,
      ],
    );
  });
}
