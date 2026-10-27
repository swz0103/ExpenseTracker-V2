import 'package:expense_tracker/src/core/ui/privacy_cover.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a sheet is covered too while the app is away', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => PrivacyCover(child: child!),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                builder: (_) => const Text('NT\$ 12,345'),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('記帳本'), findsNothing);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(find.text('記帳本'), findsOneWidget);
    // The cover is drawn over the sheet.
    final cover = tester.getRect(find.byType(ColoredBox).last);
    expect(cover.size, tester.getSize(find.byType(MaterialApp)));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('記帳本'), findsNothing);
    expect(find.text('NT\$ 12,345'), findsOneWidget);
  });
}
