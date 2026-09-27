import 'package:amount_input/amount_input.dart';
import 'package:expense_preview/split_allocation_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundation_values/foundation_values.dart';

void main() {
  Future<void> mode(WidgetTester tester, String label) async {
    await tester.tap(find.byType(DropdownButtonFormField<SplitMethod>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  Future<void> visible(WidgetTester t, Finder f) async {
    await t.ensureVisible(f);
    await t.pumpAndSettle();
  }

  Future<void> click(WidgetTester t, String label) async {
    final f = find.text(label);
    await visible(t, f);
    await t.tap(f);
    await t.pumpAndSettle();
  }

  Future<void> enter(WidgetTester t, String label, String value) async {
    final f = find.widgetWithText(TextField, label);
    await visible(t, f);
    await t.enterText(f, value);
    await t.pumpAndSettle();
  }

  Future<void> mount(
    WidgetTester tester, {
    int rows = 3,
    void Function(List<Money>?)? result,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                final p = await showDialog<List<Money>>(
                  context: context,
                  builder: (_) => SplitAllocationDialog(
                    total: Money.parse(Currency('TWD', 2), '10'),
                    labels: List.generate(rows, (i) => '分類 ${i + 1}'),
                  ),
                );
                result?.call(p);
              },
              child: const Text('開始'),
            ),
          ),
        ),
      ),
    );
    await click(tester, '開始');
  }

  testWidgets(
    'preview is explicit, equal tail is visible and cancel does not apply',
    (t) async {
      List<Money>? result;
      await mount(t, result: (p) => result = p);
      expect(
        t
            .widget<FilledButton>(find.widgetWithText(FilledButton, '套用分配'))
            .onPressed,
        null,
      );
      await click(t, '預覽分配');
      expect(find.text('3. 分類 3：TWD 3.34'), findsOneWidget);
      expect(find.text('最後一項含尾差 TWD 0.01。'), findsOneWidget);
      expect(result, null);
      await click(t, '取消');
      expect(result, null);
      expect(find.byType(AlertDialog), findsNothing);
    },
  );
  testWidgets(
    'percentage errors recover; editing invalidates proposal before explicit apply',
    (t) async {
      List<Money>? result;
      await mount(t, result: (p) => result = p);
      await mode(t, '百分比分配');
      for (var i = 1; i <= 3; i++) {
        await enter(t, '百分比 $i', '33.33');
      }
      await click(t, '預覽分配');
      expect(find.text('百分比合計必須剛好是 100%。'), findsOneWidget);
      await enter(t, '百分比 3', '33.34');
      await click(t, '預覽分配');
      expect(find.text('3. 分類 3：TWD 3.34'), findsOneWidget);
      await enter(t, '百分比 3', '1');
      expect(find.text('分配預覽'), findsNothing);
      expect(
        t
            .widget<FilledButton>(find.widgetWithText(FilledButton, '套用分配'))
            .onPressed,
        null,
      );
      await enter(t, '百分比 3', '33.34');
      await click(t, '預覽分配');
      await click(t, '套用分配');
      expect(result!.map((m) => m.majorText), ['3.33', '3.33', '3.34']);
    },
  );
  testWidgets(
    'ratio uses fractional weights and rejects overlength paste as a whole',
    (t) async {
      List<Money>? result;
      await mount(t, result: (p) => result = p);
      await mode(t, '固定比例');
      for (var i = 1; i <= 3; i++) {
        await enter(t, '比例 $i', '0.$i');
      }
      await enter(t, '比例 1', '9' * 129);
      expect(
        t
            .widget<TextField>(find.widgetWithText(TextField, '比例 1'))
            .controller!
            .text,
        '0.1',
      );
      await click(t, '預覽分配');
      await click(t, '套用分配');
      expect(result!.map((m) => m.majorText), ['1.66', '3.33', '5.01']);
    },
  );
  testWidgets(
    'sixteen rows remain scrollable at 320px and double font, including action buttons',
    (t) async {
      t.view.physicalSize = const Size(320, 900);
      t.view.devicePixelRatio = 1;
      t.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      List<Money>? result;
      await mount(t, rows: 16, result: (p) => result = p);
      await mode(t, '固定比例');
      await enter(t, '比例 16', '2');
      await click(t, '預覽分配');
      await visible(t, find.text('16. 分類 16：TWD 1.30'));
      await click(t, '套用分配');
      expect(result!.length, 16);
      expect(result!.last.majorText, '1.30');
      expect(
        result!.fold(BigInt.zero, (a, b) => a + b.minorUnits),
        BigInt.from(1000),
      );
      expect(t.takeException(), null);
    },
  );
}
