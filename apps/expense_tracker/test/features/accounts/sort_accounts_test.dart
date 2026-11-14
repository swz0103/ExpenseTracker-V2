import 'package:expense_tracker/src/app/demo/seed.dart';
import 'package:expense_tracker/src/core/look/theme.dart';
import 'package:expense_tracker/src/features/accounts/ui/accounts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a card moves as soon as its handle is dragged, from anywhere '
      'on the handle', (tester) async {
    final ledger = demoLedger();
    final first = walletAccounts(ledger).first;
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SortAccountsPage(ledger: ledger),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final handle = find.byType(ReorderableDragStartListener).first;
    // A corner of the handle, away from the lines drawn in it, with no
    // wait before moving.
    final corner = tester.getTopLeft(handle) + const Offset(6, 6);
    final drag = await tester.startGesture(corner);
    for (var i = 0; i < 10; i++) {
      await drag.moveBy(const Offset(0, 20));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await drag.up();
    await tester.pumpAndSettle();
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(walletAccounts(ledger).first.id, isNot(first.id));
  });
}
