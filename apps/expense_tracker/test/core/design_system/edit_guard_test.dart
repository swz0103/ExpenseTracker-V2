/// D83: leaving an edit form with changes asks 要捨棄修改嗎？ first,
/// however it is left; an unchanged form, or one saved, leaves at once.
library;

import 'package:expense_tracker/src/core/design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _field = ValueKey('field');
const _save = ValueKey('save');

/// A form with one field; 儲存 closes it with what was typed.
class _Form extends StatefulWidget {
  const _Form();

  @override
  State<_Form> createState() => _FormState();
}

class _FormState extends State<_Form> {
  var _text = '';

  @override
  Widget build(BuildContext context) => EditGuard(
    changed: _text.isNotEmpty,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(key: _field, onChanged: (t) => setState(() => _text = t)),
          Row(
            children: [
              const Expanded(child: CancelButton()),
              Expanded(
                child: PanelButton(
                  'save',
                  key: _save,
                  onTap: () => EditGuard.close(context, _text),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

void main() {
  /// Opens the form in a sheet; what it closed with lands in [result].
  Future<List<Object?>> open(WidgetTester tester) async {
    final result = <Object?>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async =>
                  result.add(await showSheet<String>(context, (_) => _Form())),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  Future<void> type(WidgetTester tester) async {
    await tester.enterText(find.byKey(_field), 'x');
    await tester.pumpAndSettle();
  }

  bool asked() => find.text('要捨棄修改嗎？').evaluate().isNotEmpty;

  testWidgets('an unchanged form leaves on 取消 without asking', (tester) async {
    final result = await open(tester);
    await tester.tap(find.byKey(Keys.cancelEdit));
    await tester.pumpAndSettle();
    expect(asked(), isFalse);
    expect(find.byType(_Form), findsNothing);
    expect(result, [null]);
  });

  testWidgets('取消 with changes asks; 繼續編輯 keeps the form as it was', (
    tester,
  ) async {
    await open(tester);
    await type(tester);
    await tester.tap(find.byKey(Keys.cancelEdit));
    await tester.pumpAndSettle();
    expect(asked(), isTrue);
    expect(find.text('繼續編輯'), findsOneWidget);
    await tester.tap(find.byKey(Keys.confirmCancel));
    await tester.pumpAndSettle();
    expect(find.byType(_Form), findsOneWidget);
    expect(find.text('x'), findsOneWidget);
    // Asked again the next time: still guarded.
    await tester.tap(find.byKey(Keys.cancelEdit));
    await tester.pumpAndSettle();
    expect(asked(), isTrue);
    await tester.tap(find.byKey(Keys.confirm));
    await tester.pumpAndSettle();
    expect(find.byType(_Form), findsNothing);
  });

  testWidgets('back and a tap beside the sheet ask too', (tester) async {
    await open(tester);
    await type(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(asked(), isTrue);
    await tester.tap(find.byKey(Keys.confirmCancel));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(asked(), isTrue);
    await tester.tap(find.byKey(Keys.confirmCancel));
    await tester.pumpAndSettle();
    expect(find.byType(_Form), findsOneWidget);
  });

  testWidgets('a swipe down asks, and 繼續編輯 brings the sheet back up', (
    tester,
  ) async {
    await open(tester);
    await type(tester);
    final top = tester.getTopLeft(find.byType(_Form));
    await tester.fling(find.byType(_Form), const Offset(0, 400), 2000);
    await tester.pumpAndSettle();
    expect(asked(), isTrue);
    await tester.tap(find.byKey(Keys.confirmCancel));
    await tester.pumpAndSettle();
    expect(find.byType(_Form), findsOneWidget);
    expect(tester.getTopLeft(find.byType(_Form)), top);
    expect(find.text('x'), findsOneWidget);
  });

  testWidgets('saving leaves at once, with what was saved', (tester) async {
    final result = await open(tester);
    await type(tester);
    await tester.tap(find.byKey(_save));
    await tester.pumpAndSettle();
    expect(asked(), isFalse);
    expect(result, ['x']);
  });
}
