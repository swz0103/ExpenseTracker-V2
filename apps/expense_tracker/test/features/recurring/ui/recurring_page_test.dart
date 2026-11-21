import 'package:expense_tracker/src/app/demo/seed.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/layout_checks.dart';
import '../../../support/places.dart';

/// 定期交易's calendar, with a day due that is not booked yet.
void main() {
  setUpAll(loadFonts);

  testWidgets('到期 under a day due is shown whole, at every text size', (
    tester,
  ) async {
    for (final text in [1.0, 1.5]) {
      final ledger = demoLedger();
      // Due on the 2nd, two days before the demo's today, and not booked.
      ledger.recurringCommands.saveRecurring(
        const Recurring(
          id: 'gym',
          name: '健身房',
          amount: 800,
          day: 2,
          account: 'bank',
          category: '購物休閒',
        ),
      );
      await show(tester, 360, text, book: ledger);
      await go(tester, ['更多', '定期交易']);
      expect(find.text('到期'), findsWidgets);
      expect(cutOff(tester), isEmpty, reason: 'text ${text * 100}%');
    }
  });
}
