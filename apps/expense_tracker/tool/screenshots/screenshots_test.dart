import 'dart:io';
import 'dart:ui' as ui;

import 'package:expense_tracker/src/core/look/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test/app/places.dart';

/// A picture of every page in test/app/places.dart, light and dark, on a
/// 360 × 800 dp phone at twice its density, into `$SHOTS_OUT` (default
/// build/screenshots): what CI keeps beside each build to look at a page
/// without a phone.
///
///     flutter test tool/screenshots
///
/// `SHOTS_ONLY` takes the names of the pages to draw, comma-separated.
void main() {
  setUpAll(loadFonts);
  final out = Directory(
    Platform.environment['SHOTS_OUT'] ?? 'build/screenshots',
  )..createSync(recursive: true);
  final only = Platform.environment['SHOTS_ONLY']?.split(',').toSet();
  for (final (i, (name, taps)) in places.indexed) {
    if (only != null && !only.contains(name)) continue;
    for (final dark in [false, true]) {
      final shade = dark ? 'dark' : 'light';
      testWidgets('$name, $shade', (tester) async {
        Shade.dark = dark;
        addTearDown(() => Shade.dark = false);
        final key = GlobalKey();
        await show(tester, 360, 1, height: 800, key: key);
        await go(tester, taps);
        await tester.runAsync(() async {
          final box =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await box.toImage(pixelRatio: 2);
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          final number = '${i + 1}'.padLeft(2, '0');
          File('${out.path}/$number $name $shade.png')
              .writeAsBytesSync(png!.buffer.asUint8List());
        });
      });
    }
  }
}
