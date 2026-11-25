import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import 'motion.dart';
import 'shape.dart';
import 'theme.dart';
import '../formatting/setting_topic.dart';

/// The setting a search looked for, told to the [Findable]s of the page
/// under it; none when the page was opened another way.
class FindScope extends InheritedWidget {
  const FindScope({super.key, required this.sought, required super.child});

  final SettingTopic? sought;

  static SettingTopic? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FindScope>()?.sought;

  @override
  bool updateShouldNotify(FindScope oldWidget) => sought != oldWidget.sought;
}

/// [child], a setting search finds by [topic]. When the page was opened
/// on it ([FindScope]), it is scrolled into view, framed in the accent for
/// a moment, and a screen reader says it was found. While the phone asks
/// for less motion, the frame stays without fading, and the page does not
/// glide to it.
class Findable extends StatefulWidget {
  const Findable({super.key, required this.topic, required this.child});

  final SettingTopic topic;
  final Widget child;

  @override
  State<Findable> createState() => _FindableState();
}

class _FindableState extends State<Findable>
    with SingleTickerProviderStateMixin {
  /// Shown once, when the page opens on it; null before and after.
  AnimationController? _glow;

  /// Framed for good: motion is off.
  var _still = false;

  /// Whether it has been shown for this opening.
  var _shown = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_shown || FindScope.of(context) != widget.topic) return;
    _shown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _show());
  }

  void _show() {
    if (!mounted) return;
    _still = MediaQuery.disableAnimationsOf(context);
    if (!_still) {
      // Held for most of the time, then faded out.
      _glow = AnimationController(
        vsync: this,
        duration: Motion.of(context, Motion.extraLong1 * 3),
      )..forward();
    }
    setState(() {});
    Scrollable.ensureVisible(
      context,
      alignment: 0.3,
      duration: Motion.of(context, Motion.medium2),
    ).ignore();
    SemanticsService.sendAnnouncement(
      View.of(context),
      widget.topic.foundSaid,
      Directionality.of(context),
    ).ignore();
  }

  @override
  void dispose() {
    _glow?.dispose();
    super.dispose();
  }

  Widget _framed(double strength) => strength <= 0
      ? widget.child
      : Container(
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.large),
            border: Border.all(
              color: AppColors.accent.withValues(alpha: strength),
              width: 3,
            ),
          ),
          child: widget.child,
        );

  @override
  Widget build(BuildContext context) {
    if (_still) return _framed(1);
    final glow = _glow;
    if (glow == null) return widget.child;
    return AnimatedBuilder(
      animation: glow,
      builder: (context, child) =>
          _framed(1 - const Interval(0.7, 1).transform(glow.value)),
    );
  }
}
