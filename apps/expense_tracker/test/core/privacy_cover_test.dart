import 'package:expense_tracker/src/core/ui/privacy_cover.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final blur = find.byKey(const ValueKey('privacy-blur'));

  Future<void> show(
    WidgetTester tester, {
    Future<bool> Function()? systemHides,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            PrivacyCover(systemHides: systemHides, child: child!),
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
  }

  testWidgets('a sheet is blurred too while the app is away', (tester) async {
    await show(tester);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(blur, findsNothing);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(blur, findsOneWidget);
    // Over the whole app, the sheet included.
    expect(tester.getSize(blur), tester.getSize(find.byType(MaterialApp)));
    expect(find.text('記帳本'), findsNothing, reason: 'no name panel');

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(blur, findsNothing);
    expect(find.text('NT\$ 12,345'), findsOneWidget);
  });

  testWidgets('nothing is blurred when the phone hides the app itself', (
    tester,
  ) async {
    await show(tester, systemHides: () async => true);
    await tester.pump();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(blur, findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
  });
}
