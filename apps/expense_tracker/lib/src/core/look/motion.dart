import 'package:flutter/widgets.dart';

/// How long a change on the screen takes, in step with the person's
/// settings: none at all when they asked the phone to reduce motion
/// (`MediaQuery.disableAnimationsOf`), else [Motion.of]'s duration. Every
/// animation the screens run goes through here (a rule in
/// design_rules_test), so turning motion off turns all of it off.
abstract final class Motion {
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
