import 'package:expense_tracker/src/core/design_system/keys.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/features/recurring/ui/held_bookings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// D61: what the automatic booking left is asked once, then booked each
/// on its day.
void main() {
  Ledger book() => Ledger(
    today: DateTime.utc(2026, 11, 13),
    accounts: const [Account('bank', '銀行', AccountKind.bank, 500000)],
    categories: [Category('居家', 'home', 0xFF5B8DB0)],
    entries: [
      Entry(
        id: 'aug',
        date: DateTime.utc(2026, 8, 1),
        type: EntryType.expense,
        amount: 15000,
        account: 'bank',
        category: '居家',
        recurring: 'rent',
      ),
    ],
    holdings: const [],
    budgets: const [],
    recurring: [
      Recurring(
        id: 'rent',
        name: '房租',
        amount: 15000,
        day: 1,
        account: 'bank',
        category: '居家',
        auto: true,
        start: DateTime.utc(2026, 1, 1),
      ),
    ],
  );

  Future<BuildContext> host(WidgetTester tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (c) {
              context = c;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    return context;
  }

  testWidgets('more than one day waiting is asked, then booked; not asked '
      'again', (tester) async {
    final ledger = book();
    final due = ledger.recurringCommands.bookDue();
    final context = await host(tester);
    final told = HeldBookings();
    final notices = <String>[];
    Future<void> notice(String title, String text) async => notices.add(title);

    final asking = told.tell(
      context,
      ledger,
      due.booked,
      due.held,
      notice: notice,
    );
    await tester.pumpAndSettle();
    expect(find.text('有定期交易多期尚未入帳'), findsOneWidget);
    expect(find.textContaining('「房租」3 期（9/1–11/1）'), findsOneWidget);
    await tester.tap(find.byKey(Keys.confirm));
    await tester.pumpAndSettle();
    await asking;
    // August was booked; September to November now too.
    expect(ledger.entries.length, 4);
    expect(find.text('已記下 3 筆定期交易'), findsOneWidget);
    expect(notices, isEmpty);

    // The same days are not asked about twice.
    await told.tell(context, ledger, 0, due.held, notice: notice);
    await tester.pumpAndSettle();
    expect(find.text('有定期交易多期尚未入帳'), findsNothing);
  });

  testWidgets('what cannot be booked by itself is told once', (tester) async {
    final ledger = book();
    final context = await host(tester);
    final notices = <String>[];
    await HeldBookings().tell(context, ledger, 1, [
      HeldBooking(ledger.recurring.all.single, [
        DateTime.utc(2026, 11, 1),
      ], closed: true),
    ], notice: (title, text) async => notices.add('$title|$text'));
    await tester.pump();
    expect(find.text('已自動記下 1 筆定期交易'), findsOneWidget);
    expect(notices, ['定期交易未自動入帳|「房租」的帳戶已封存，11/1 起沒有自動入帳']);
  });
}
