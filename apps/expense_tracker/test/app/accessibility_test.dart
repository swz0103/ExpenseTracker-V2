import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'dart:ui' show Tristate;

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
      for (final words in unpressable(tester)) {
        faults.add('$name: 「$words」 is read as a button but cannot be pressed');
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

/// What a screen reader calls a button but cannot press: a button whose
/// own tap was left out with the words under it (`excludeSemantics`),
/// so double-tapping it with TalkBack does nothing.
List<String> unpressable(WidgetTester tester) {
  final found = <String>[];
  void visit(SemanticsNode node) {
    final data = node.getSemanticsData();
    if (data.flagsCollection.isButton &&
        data.flagsCollection.isEnabled != Tristate.isFalse &&
        !data.hasAction(SemanticsAction.tap) &&
        !node.isMergedIntoParent) {
      found.add(data.label.replaceAll('\n', ' '));
    }
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  for (final view in tester.binding.renderViews) {
    final root = view.owner?.semanticsOwner?.rootSemanticsNode;
    if (root != null) visit(root);
  }
  return found;
}

/// The words on screen drawn in the style Flutter gives text with no
/// Material above it: a yellow double underline.
List<String> unstyled(WidgetTester tester) => [
  for (final text in tester.widgetList<RichText>(find.byType(RichText)))
    if (text.text.style?.decorationStyle == TextDecorationStyle.double &&
        text.text.style?.decorationColor == const Color(0xFFFFFF00))
      text.text.toPlainText(),
];
