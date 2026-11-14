import 'package:expense_tracker/src/app/demo/seed.dart';
import 'package:expense_tracker/src/app/shell.dart';
import 'package:expense_tracker/src/core/look/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a screen reader moves a category with 往後移 and 往前移, '
      'kept at once', (tester) async {
    final handle = tester.ensureSemantics();
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final ledger = demoLedger();
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: AppShell(ledger: ledger),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('分類').first);
    await tester.pumpAndSettle();

    List<String> tops() => [
      for (final c in ledger.categoriesFor(income: false))
        if (c.parent == null) c.name,
    ];
    final before = tops();
    final first = before.first;

    void act(String name, String label) {
      final node = tester.getSemantics(find.text(name).last);
      // The tile's own node, or the one above it that carries the moves.
      SemanticsNode? carrier = node;
      while (carrier != null &&
          !carrier.getSemanticsData().customSemanticsActionIds!.any(
            (id) => CustomSemanticsAction.getAction(id)?.label == label,
          )) {
        carrier = carrier.parent;
      }
      expect(carrier, isNotNull, reason: 'no 「$label」 on $name');
      final id = carrier!
          .getSemanticsData()
          .customSemanticsActionIds!
          .firstWhere(
            (id) => CustomSemanticsAction.getAction(id)?.label == label,
          );
      tester
          .renderObject(find.byType(AppShell))
          .owner!
          .semanticsOwner!
          .performAction(carrier.id, SemanticsAction.customAction, id);
    }

    act(first, '往後移');
    await tester.pumpAndSettle();
    expect(tops().indexOf(first), 1);
    act(first, '往前移');
    await tester.pumpAndSettle();
    expect(tops(), before);
    handle.dispose();
  });
}
