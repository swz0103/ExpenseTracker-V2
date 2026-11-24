import 'package:expense_tracker/src/core/design_system/dialogs.dart';
import 'package:expense_tracker/src/core/design_system/keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/android_text_scale.dart';
import '../../support/places.dart' show loadFonts;

void main() {
  setUpAll(loadFonts);

  /// A page whose button asks [confirm] with a long body, answering into
  /// [answers].
  Widget page(List<bool> answers) => MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: const AndroidTextScaler200()),
      child: child!,
    ),
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: TextButton(
            key: const ValueKey('ask'),
            onPressed: () async => answers.add(
              await confirm(
                context,
                '刪除舊備份',
                '刪除',
                danger: true,
                body: List.filled(12, '這些備份用舊的金鑰加密，刪除後無法再還原。').join(),
              ),
            ),
            child: const Text('ask'),
          ),
        ),
      ),
    ),
  );

  testWidgets('a confirm with a long body scrolls it and keeps both choices '
      'in view, at 320 dp and 200% text', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final answers = <bool>[];
    await tester.pumpWidget(page(answers));
    await tester.tap(find.byKey(const ValueKey('ask')));
    await tester.pumpAndSettle();
    // No overflow: the words are in a scroll view, the choices are not.
    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    final confirmBox = tester.getRect(find.byKey(Keys.confirm));
    expect(confirmBox.bottom, lessThanOrEqualTo(screen.height));
    await tester.tap(find.byKey(Keys.confirm));
    await tester.pumpAndSettle();
    expect(answers, [true]);
  });
}
