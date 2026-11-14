import 'package:expense_tracker/src/core/look/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'places.dart';

/// Every page and tab, the panels in the middle of the screen and each
/// page of 記一筆, on a small phone (320 dp), a common one (360 dp) and a
/// large one (412 dp), with the text at 100%, 130% and 150%, and in dark
/// at 360 dp: nothing overflows, no words are drawn over other words, and
/// none are shrunk to fit below six tenths of their size. Words
/// running into each other, or a block too small for what it holds, is
/// how a page breaks on a real phone though it looked right at one size.
void main() {
  setUpAll(loadFonts);

  for (final (width, text, dark) in [
    for (final width in const [320.0, 360.0, 412.0])
      for (final text in const [1.0, 1.3, 1.5]) (width, text, false),
    (360.0, 1.0, true),
    (360.0, 1.5, true),
  ]) {
    testWidgets('${width.toInt()} dp, text ${(text * 100).round()}%'
        '${dark ? ', dark' : ''}: '
        'nothing overflows and no words overlap', (tester) async {
      Shade.dark = dark;
      addTearDown(() => Shade.dark = false);
      final faults = <String>[];
      for (final (name, taps) in places) {
        await show(tester, width, text);
        await go(tester, taps);
        final error = tester.takeException();
        if (error != null) faults.add('$name: $error');
        final shrunk = <String>[];
        for (final (a, b) in overlapping(tester, shrunk)) {
          faults.add('$name: 「$a」 overlaps 「$b」');
        }
        for (final words in shrunk) {
          faults.add('$name: 「$words」 shrunk too small to read');
        }
        for (final words in withoutAppFont(tester)) {
          faults.add('$name: 「$words」 not in the app\'s fonts');
        }
      }
      expect(faults, isEmpty, reason: faults.join('\n'));
    });
  }
}

/// Words drawn in a font the app does not bring, such as a button whose
/// style left the family out: the phone then draws them in its own font.
List<String> withoutAppFont(WidgetTester tester) {
  const ours = {'Nunito', 'NotoSansTC', 'MaterialIcons'};
  final found = <String>[];
  for (final element in find.byType(RichText).evaluate()) {
    final route = ModalRoute.of(element);
    if (route != null && !route.isCurrent) continue;
    final box = element.renderObject;
    if (box is! RenderParagraph) continue;
    var plain = true;
    box.text.visitChildren((span) {
      if (span is TextSpan && (span.text ?? '').trim().isNotEmpty) {
        final family = span.style?.fontFamily ?? box.text.style?.fontFamily;
        if (family == null || !ours.contains(family)) plain = false;
      }
      return plain;
    });
    if (!plain) found.add(box.text.toPlainText().trim());
  }
  return found;
}

/// Pairs of words drawn over each other on screen: each run of words is
/// measured by the boxes its glyphs take, not the box laid out for it,
/// so words that only sit near each other do not count.
List<(String, String)> overlapping(
  WidgetTester tester, [
  List<String>? shrunk,
]) {
  final small = shrunk ?? <String>[];
  final bottom = tester.view.physicalSize.height / tester.view.devicePixelRatio;
  final runs = <(String, Rect)>[];
  for (final element in find.byType(RichText).evaluate()) {
    // Only the page or sheet on top: what lies under a sheet is covered.
    final route = ModalRoute.of(element);
    if (route != null && !route.isCurrent) continue;
    final box = element.renderObject;
    if (box is! RenderParagraph || !box.hasSize || !box.attached) continue;
    final words = box.text.toPlainText().trim();
    if (words.isEmpty) continue;
    final boxes = box.getBoxesForSelection(
      TextSelection(baseOffset: 0, extentOffset: box.text.toPlainText().length),
    );
    if (boxes.isEmpty) continue;
    var rect = boxes.first.toRect();
    for (final b in boxes.skip(1)) {
      rect = rect.expandToInclude(b.toRect());
    }
    // Words cut off by their own box, such as an ellipsis, only count
    // where they are drawn.
    rect = rect.intersect(Offset.zero & box.size);
    if (rect.isEmpty) continue;
    // Through every transform above it, such as a FittedBox scaling the
    // words down: what is drawn, not what was laid out.
    final drawn = MatrixUtils.transformRect(box.getTransformTo(null), rect);
    // Shrunk to fit below six tenths of its size, words cannot be read.
    if (drawn.height < rect.height * 0.6) {
      small.add(words);
    }
    // Only what is seen: cut by every clip above it, such as a row that
    // slides sideways, and not under the tab bar along the bottom.
    var seen = drawn;
    RenderObject child = box;
    var parent = box.parent;
    while (parent != null && !seen.isEmpty) {
      final clip = parent.describeApproximatePaintClip(child);
      if (clip != null) {
        seen = seen.intersect(
          MatrixUtils.transformRect(parent.getTransformTo(null), clip),
        );
      }
      child = parent;
      parent = parent.parent;
    }
    if (seen.isEmpty || seen.width <= 0 || seen.height <= 0) continue;
    if (seen.top > bottom - 110) continue;
    runs.add((words, seen));
  }
  final found = <(String, String)>[];
  for (var i = 0; i < runs.length; i++) {
    for (var j = i + 1; j < runs.length; j++) {
      final both = runs[i].$2.intersect(runs[j].$2);
      // A pixel of touching ascenders is not two words on each other.
      if (both.width > 2 && both.height > 2) {
        found.add((runs[i].$1, runs[j].$1));
      }
    }
  }
  return found;
}
