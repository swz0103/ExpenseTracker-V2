import 'package:expense_tracker/src/core/design_system/keys.dart';
import 'package:expense_tracker/src/core/widgets/lock_cover.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final cover = find.byKey(Keys.lockCover);
  const amount = 'NT\$ 12,345';

  /// A page with a button that counts its taps and opens a sheet with an
  /// amount on it, under the cover.
  Future<void> show(
    WidgetTester tester,
    List<String> taps, {
    required bool covered,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => LockCover(covered: covered, child: child!),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () {
                taps.add('open');
                showModalBottomSheet<void>(
                  context: context,
                  builder: (_) => const Text(amount),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('uncovered, the screens show, are read out and take taps', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final taps = <String>[];
    await show(tester, taps, covered: false);
    expect(cover, findsNothing);
    expect(find.semantics.byLabel('open'), findsOneWidget);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(taps, ['open']);
    expect(find.text(amount), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('covered, a sheet is under the cover too: nothing of it is '
      'read out or takes a tap, and it is still there when uncovered', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final taps = <String>[];
    await show(tester, taps, covered: false);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await show(tester, taps, covered: true);
    await tester.pump();
    expect(cover, findsOneWidget);
    // Over the whole app, sheet included.
    expect(tester.getSize(cover), tester.getSize(find.byType(MaterialApp)));
    expect(find.semantics.byLabel(amount), findsNothing);
    expect(find.semantics.byLabel('open'), findsNothing);
    await tester.tapAt(tester.getCenter(find.text('open')));
    await tester.pump();
    expect(taps, ['open'], reason: 'no tap went through');

    await show(tester, taps, covered: false);
    await tester.pump();
    expect(cover, findsNothing);
    expect(find.text(amount), findsOneWidget, reason: 'state kept');
    expect(find.semantics.byLabel(amount), findsOneWidget);
    semantics.dispose();
  });
}
