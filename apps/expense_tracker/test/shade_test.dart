import 'package:expense_tracker/src/look/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Words keep the colour they were laid out in until their paragraph is
/// built again, and a [Shade] is the same object in both modes: these
/// check that [Shade.show] makes what is on screen take the other mode's
/// colours, read from the painted pixels, not only from the [Shade].
void main() {
  const boundary = Key('words');

  Future<void> show(WidgetTester tester) async {
    // The test font draws each letter as a filled square, so the middle
    // of the word is wholly in its colour.
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: RepaintBoundary(
            key: boundary,
            child: Text('M', style: TextStyle(fontSize: 40, color: Hue.ink)),
          ),
        ),
      ),
    );
  }

  /// The colour painted in the middle of the words, as 0xAARRGGBB.
  Future<int> painted(WidgetTester tester) async {
    final box = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(boundary),
    );
    final read = await tester.runAsync(() async {
      final image = await box.toImage();
      final bytes = await image.toByteData();
      final size = (image.width, image.height);
      image.dispose();
      return (bytes, size);
    });
    final (bytes, (width, height)) = read!;
    final at = ((height ~/ 2) * width + width ~/ 2) * 4;
    final data = bytes!;
    return data.getUint8(at + 3) << 24 |
        data.getUint8(at) << 16 |
        data.getUint8(at + 1) << 8 |
        data.getUint8(at + 2);
  }

  /// Whether [argb] is [expected] to within rounding.
  Matcher near(int expected) => predicate<int>((argb) {
    for (final shift in const [0, 8, 16, 24]) {
      final a = argb >> shift & 0xFF;
      final b = expected >> shift & 0xFF;
      if ((a - b).abs() > 2) return false;
    }
    return true;
  }, 'within 2 of 0x${expected.toRadixString(16)} in each channel');

  testWidgets('words in Hue.ink are painted afresh in the dark colour', (
    tester,
  ) async {
    addTearDown(() => Shade.dark = false);
    await show(tester);
    final paragraph = tester.renderObject<RenderParagraph>(find.text('M'));
    expect(paragraph.text.style?.color, same(Hue.ink));
    expect(await painted(tester), near(Hue.ink.light));

    Shade.show(dark: true);
    await tester.pump();
    expect(
      tester.renderObject<RenderParagraph>(find.text('M')),
      same(paragraph),
      reason: 'the words change colour in place',
    );
    expect(await painted(tester), near(Hue.ink.darkValue));

    Shade.show(dark: false);
    await tester.pump();
    expect(await painted(tester), near(Hue.ink.light));
  });
}
