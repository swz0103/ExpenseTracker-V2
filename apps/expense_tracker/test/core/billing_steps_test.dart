import 'dart:math';

import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:flutter_test/flutter_test.dart';

/// A purchase in instalments, as dated steps, bills exactly what the
/// statement rules say it has billed by any day: the steps are what the
/// balances are worked out from, so they must never differ.
void main() {
  test('the steps up to a day add up to what was billed by then', () {
    final r = Random(5);
    final cards = [
      const Account('k1', '卡', AccountKind.card, 0, closingDay: 20, dueDay: 5),
      const Account('k2', '卡', AccountKind.card, 0, closingDay: 31, dueDay: 15),
      Account(
        'k3',
        '卡',
        AccountKind.card,
        0,
        closingDay: 5,
        dueDay: 25,
        closes: {DateTime.utc(2026, 3, 5): DateTime.utc(2026, 3, 3)},
      ),
    ];
    var checked = 0;
    for (var i = 0; i < 300; i++) {
      final card = cards[r.nextInt(cards.length)];
      final e = Entry(
        id: 'e$i',
        date: DateTime.utc(2025, 1 + r.nextInt(24), 1 + r.nextInt(28)),
        type: EntryType.expense,
        amount: 100 + r.nextInt(99900),
        account: card.id,
        category: '購物',
        installments: 2 + r.nextInt(23),
      );
      final steps = card.billingSteps(e);
      expect(steps, hasLength(e.installments));
      expect(steps.fold(0, (s, x) => s + x.$2), e.amount);
      for (var d = 0; d < 40; d++) {
        final at = e.date.add(Duration(days: r.nextInt(800) - 30));
        final summed = steps
            .where((s) => !s.$1.isAfter(at))
            .fold(0, (s, x) => s + x.$2);
        expect(summed, card.billed(e, at), reason: '${e.id} at $at');
        checked++;
      }
    }
    expect(checked, 12000);
  });
}
