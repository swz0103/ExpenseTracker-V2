// ENT-04: what the calculator shows is what it keeps. A sum that is not
// an amount says why, and 完成 waits instead of keeping another amount.
import 'package:expense_tracker/src/core/design_system/keys.dart';
import 'package:expense_tracker/src/core/formatting/words.dart';
import 'package:expense_tracker/src/core/widgets/calculator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// Opens the calculator on [initial] in [unit], presses [keys], then
  /// 完成; what it returned, and whether it is still open.
  Future<(int?, bool)> press(
    WidgetTester tester,
    List<String> keys, {
    int initial = 500,
    String unit = 'TWD',
  }) async {
    int? kept;
    var closed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                kept = await showCalculator(
                  context,
                  title: '金額',
                  initial: initial,
                  color: Colors.red,
                  unit: unit,
                );
                closed = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    for (final key in keys) {
      await tester.tap(find.byKey(Keys.calc(key)));
      await tester.pump();
    }
    await tester.tap(find.byKey(Keys.calc(Words.done)));
    await tester.pumpAndSettle();
    return (kept, closed);
  }

  String? problem() {
    final found = find.byKey(Keys.calcProblem);
    return found.evaluate().isEmpty
        ? null
        : (found.evaluate().single.widget as Text).data;
  }

  testWidgets('5÷0 says so and does not clear the amount to 0', (tester) async {
    final (kept, closed) = await press(tester, ['C', '5', '÷', '0']);
    expect(closed, isFalse);
    expect(kept, isNull);
    expect(problem(), '不能除以 0');
  });

  testWidgets('12−20 shows −8 and is not kept as 0', (tester) async {
    final (kept, closed) = await press(tester, ['C', '1', '2', '−', '2', '0']);
    expect(closed, isFalse);
    expect(kept, isNull);
    expect(find.text('−8'), findsOneWidget);
    expect(problem(), '金額不能小於 0');
  });

  testWidgets('1,234,567,890 is shown as typed and not cut to 999,999,999', (
    tester,
  ) async {
    final (kept, closed) = await press(tester, [
      'C',
      ...'1234567890'.split(''),
    ]);
    expect(closed, isFalse);
    expect(kept, isNull);
    expect(find.text('1,234,567,890'), findsOneWidget);
    expect(problem(), '金額不能超過 999,999,999');
  });

  testWidgets('an amount is kept as shown', (tester) async {
    // 7 / 2 = 3.5 -> 4, shown and kept alike.
    final (kept, closed) = await press(tester, ['C', '7', '÷', '2']);
    expect(closed, isTrue);
    expect(kept, 4);
  });

  testWidgets('US cents are kept exactly', (tester) async {
    // 0.1 + 0.2 = 0.30 US$ = 30 cents.
    final (kept, _) = await press(tester, [
      'C',
      '.',
      '1',
      '+',
      '.',
      '2',
    ], unit: 'USD');
    expect(kept, 30);
  });

  testWidgets('the initial amount is offered as typed', (tester) async {
    // 1250 US cents start as 12.50; 完成 keeps them.
    final (kept, _) = await press(tester, const [], initial: 1250, unit: 'USD');
    expect(kept, 1250);
  });

  testWidgets('F107: the keys are named for a screen reader', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showCalculator(
                context,
                title: '金額',
                initial: 0,
                color: Colors.red,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    for (final label in ['減', '加', '乘以', '除以', '兩個零', '三個零', '清除', '刪除']) {
      expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
    }
    handle.dispose();
  });
}
