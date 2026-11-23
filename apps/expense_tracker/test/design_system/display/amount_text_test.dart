import 'package:expense_tracker/design_system/display/amount_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> show(WidgetTester tester, Widget child) =>
      tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));

  testWidgets('F107: an amount is read with its direction, not its sign', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await show(tester, AmountText.of(1844, sense: AmountSense.spending));
    // Seen with a true minus, heard as 支出.
    expect(find.text('−1,844'), findsOneWidget);
    expect(find.bySemanticsLabel('支出 1,844 元'), findsOneWidget);
    expect(find.bySemanticsLabel('−1,844'), findsNothing);
    handle.dispose();
  });

  testWidgets('a foreign amount is read with its currency name', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await show(tester, AmountText.of(1250, currency: 'USD'));
    expect(find.text('USD 12.50'), findsOneWidget);
    expect(find.bySemanticsLabel('美元 12.50'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('a hidden amount shows dots and is not read out', (tester) async {
    final handle = tester.ensureSemantics();
    await show(
      tester,
      AmountText.of(25000, sense: AmountSense.income, hidden: true),
    );
    expect(find.text('••••'), findsOneWidget);
    expect(find.bySemanticsLabel('收入 金額已隱藏'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('an amount written its own way keeps its words', (tester) async {
    final handle = tester.ensureSemantics();
    await show(tester, const AmountText('−200', spoken: '支出 200 元'));
    expect(find.text('−200'), findsOneWidget);
    expect(find.bySemanticsLabel('支出 200 元'), findsOneWidget);
    handle.dispose();
  });
}
