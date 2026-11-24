import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/places.dart';
import '../../../support/seeded_book.dart' show emptyBook;

/// 折合新台幣 under a foreign amount: a day gone by is valued at today's
/// rate only as an estimate, and says so (R5; review 16: the 以今日臺銀…
/// wording, reached as the phone checklist does, by booking a foreign
/// recurring item's day gone by).
void main() {
  testWidgets('a foreign recurring item booked for a day gone by says its '
      'NT\$ worth is an estimate at today\'s rate', (tester) async {
    // Today 2026-10-31; US$10 due on the 2nd, not booked; USD at 32.
    final ledger = emptyBook(
      recurring: [
        const Recurring(
          id: 'cloud',
          name: '雲端空間',
          amount: 1000,
          day: 2,
          account: 'usd',
          category: '娛樂',
        ),
      ],
    );
    await show(tester, 360, 1, height: 1600, book: ledger);
    await go(tester, ['更多', '定期交易', '入帳']);
    expect(find.text('以今日臺銀即期買入 32.0 估算，請改成當日金額'), findsOneWidget);
  });
}
