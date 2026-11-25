import 'package:expense_tracker/src/core/design_system/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'dart:ui' show Tristate;

import 'package:flutter_test/flutter_test.dart';

import '../support/built_places.dart';
import '../support/places.dart';

/// Every place a person reaches (places.dart), checked against Android's
/// accessibility guidelines: each tap target at least 48 dp and named for
/// a screen reader, and no words drawn in Flutter's warning style, the
/// yellow double underline of text with no Material above it. How each
/// page holds with large text is layout_*_test.dart's.
///
/// [unstyled] is used by test/core/widgets/tour_test.dart too.
/// The places with a row of seven day cells (DAY-01).
const sevenAcross = {'總覽', '定期交易'};

void main() {
  setUpAll(loadFonts);

  // Android's guidelines hold on the smallest phones too, where a row
  // of targets has the least room: 320 and 360 dp as well as 400.
  for (final width in [320.0, 360.0, 400.0]) {
    for (final place in allPlaces) {
      testWidgets('${width.toInt()} dp, ${place.name}: tap targets are 48 dp '
          'and named', (tester) async {
        final semantics = tester.ensureSemantics();
        final faults = <String>[];
        await place.open(tester, Look(width, 1, height: 2600));
        for (final words in unstyled(tester)) {
          faults.add('「$words」 has no text style');
        }
        for (final words in readTwice(tester)) {
          faults.add('「$words」 is read out twice');
        }
        for (final words in unpressable(tester)) {
          faults.add('「$words」 is read as a button but cannot be pressed');
        }
        for (final guideline in [
          // Seven day cells across are narrower than 48 dp on a phone under
          // about 376 dp: the owner's open decision (known defect DAY-01).
          if (!(width < 376 && sevenAcross.contains(place.name)))
            androidTapTargetGuideline,
          labeledTapTargetGuideline,
        ]) {
          final result = await guideline.evaluate(tester);
          if (!result.passed) faults.add('${result.reason}');
        }
        semantics.dispose();
        expect(faults, isEmpty, reason: faults.join('\n'));
      });
    }
  }

  // The dark theme's words on their grounds, 4.5:1, on the places of the
  // newer screens: the older pages' own contrast is its own work (the
  // investment form's tabs, the pickers' day names).
  for (final place in [
    ...reviewPlaces.where((p) => !p.name.contains('買進')),
    ...builtPlaces,
  ]) {
    testWidgets('dark, ${place.name}: words read at 4.5:1', (tester) async {
      Shade.dark = true;
      addTearDown(() => Shade.dark = false);
      final semantics = tester.ensureSemantics();
      await place.open(tester, const Look(360, 1, height: 2600));
      final result = await textContrastGuideline.evaluate(tester);
      semantics.dispose();
      expect(result.passed, isTrue, reason: '${result.reason}');
    });
  }
}

/// Names a screen reader reads with the same words twice: a card's own
/// label followed by the words it was made from.
List<String> readTwice(WidgetTester tester) {
  final found = <String>[];
  void visit(SemanticsNode node) {
    final parts = [
      for (final part in node.label.split(RegExp('[\n，]')))
        if (part.trim().length > 1) part.trim(),
    ];
    if (parts.toSet().length < parts.length) {
      found.add(node.label.replaceAll('\n', ' '));
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
