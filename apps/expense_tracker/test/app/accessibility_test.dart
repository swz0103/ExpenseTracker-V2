import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'places.dart';

/// Every place a person reaches (places.dart), checked against Android's
/// accessibility guidelines: each tap target at least 48 dp and named for
/// a screen reader, and no words drawn in Flutter's warning style, the
/// yellow double underline of text with no Material above it. How each
/// page holds with large text is layout_*_test.dart's.
///
/// [unstyled] is used by test/core/tour_test.dart too.
void main() {
  setUpAll(loadFonts);

  testWidgets('tap targets are 48 dp and named on every page', (tester) async {
    final semantics = tester.ensureSemantics();
    final faults = <String>[];
    for (final (name, taps) in places) {
      await show(tester, 400, 1, height: 2600);
      await go(tester, taps);
      for (final words in unstyled(tester)) {
        faults.add('$name: 「$words」 has no text style');
      }
      for (final guideline in [
        androidTapTargetGuideline,
        labeledTapTargetGuideline,
      ]) {
        final result = await guideline.evaluate(tester);
        if (!result.passed) faults.add('$name: ${result.reason}');
      }
    }
    semantics.dispose();
    expect(faults, isEmpty, reason: faults.join('\n'));
  });
}

/// The words on screen drawn in the style Flutter gives text with no
/// Material above it: a yellow double underline.
List<String> unstyled(WidgetTester tester) => [
  for (final text in tester.widgetList<RichText>(find.byType(RichText)))
    if (text.text.style?.decorationStyle == TextDecorationStyle.double &&
        text.text.style?.decorationColor == const Color(0xFFFFFF00))
      text.text.toPlainText(),
];
