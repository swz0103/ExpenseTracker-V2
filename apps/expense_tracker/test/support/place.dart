import 'package:expense_tracker/src/core/design_system/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// How a place is looked at: the phone's [width] and [height], the text at
/// [text] times its size or exactly [scaler], and motion turned off when
/// [still].
final class Look {
  const Look(
    this.width,
    this.text, {
    this.height = 2800,
    this.still = false,
    this.scaler,
  });

  final double width;
  final double text;
  final double height;
  final bool still;
  final TextScaler? scaler;
}

/// A place a person reaches: its [name], and how to bring it to the
/// screen as `look` says (`open`). The layout, accessibility and motion
/// suites run every one.
final class Place {
  const Place(this.name, this.open);

  final String name;
  final Future<void> Function(WidgetTester tester, Look look) open;
}

/// Puts [home] on a phone as [look] says, in the app's own theme, a new
/// app each time, then lets it settle: [forTime] of animation frames, for
/// screens that never stop moving (a spinner) or that arrive.
Future<void> showScene(
  WidgetTester tester,
  Look look,
  Widget home, {
  double? height,
  Duration forTime = const Duration(seconds: 3),
}) async {
  tester.view.physicalSize = Size(look.width, height ?? look.height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      key: UniqueKey(),
      debugShowCheckedModeBanner: false,
      theme: appTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: look.scaler ?? TextScaler.linear(look.text),
          disableAnimations: look.still,
        ),
        child: child!,
      ),
      home: home,
    ),
  );
  await tester.pump();
  for (
    var t = Duration.zero;
    t < forTime;
    t += const Duration(milliseconds: 100)
  ) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
