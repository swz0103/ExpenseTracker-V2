import 'package:flutter/widgets.dart';

/// How long a change on the screen takes, in step with the person's
/// settings: none at all when they asked the phone to reduce motion
/// (`MediaQuery.disableAnimationsOf`), else [Motion.of]'s duration. Every
/// animation the screens run goes through here (a rule in
/// design_rules_test), so turning motion off turns all of it off.
abstract final class Motion {
  // How long a change takes, on Material 3's scale (m3.material.io,
  // Styles, Motion, Easing and duration): short for small things that
  // change in place, medium for what moves or grows within a screen, long
  // and extra long for what crosses it or comes in whole.

  /// 100 ms: a press.
  static const short2 = Duration(milliseconds: 100);

  /// 150 ms: a tick or a switch.
  static const short3 = Duration(milliseconds: 150);

  /// 200 ms: a choice marked, a fold, a release.
  static const short4 = Duration(milliseconds: 200);

  /// 250 ms: a page or a part of one turning to the next.
  static const medium1 = Duration(milliseconds: 250);

  /// 300 ms: a card turning, a figure changing.
  static const medium2 = Duration(milliseconds: 300);

  /// 350 ms: something coming into sight.
  static const medium3 = Duration(milliseconds: 350);

  /// 400 ms: a chart's bars growing.
  static const medium4 = Duration(milliseconds: 400);

  /// 500 ms: something moving across the screen.
  static const long2 = Duration(milliseconds: 500);

  /// 600 ms: a screen coming in whole.
  static const long4 = Duration(milliseconds: 600);

  /// 700 ms: a chart drawn from nothing.
  static const extraLong1 = Duration(milliseconds: 700);

  /// [duration], or none while motion is turned off.
  static Duration of(BuildContext context, Duration duration) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;
}

/// [child] growing and shrinking to its size over [duration], as
/// `AnimatedSize` does; while motion is off, [child] at its size at once.
/// `AnimatedSize` given no time at all trips over its own layout, so it is
/// left out rather than given none.
class MotionSize extends StatelessWidget {
  const MotionSize({
    super.key,
    required this.duration,
    this.curve = Curves.linear,
    this.alignment = Alignment.center,
    required this.child,
  });

  final Duration duration;
  final Curve curve;
  final Alignment alignment;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return AnimatedSize(
      duration: duration,
      curve: curve,
      alignment: alignment,
      child: child,
    );
  }
}
