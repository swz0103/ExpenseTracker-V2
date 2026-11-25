import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/design_system/app_mark.dart';
import '../../../../core/design_system/theme.dart';
import '../../../../core/design_system/components/buttons.dart';
import '../../../../core/design_system/keys.dart';
import '../../../../core/design_system/shape.dart';
import '../../../../core/design_system/spacing.dart';
import '../../../../core/widgets/diagnostics_button.dart';

/// The page every lock screen form sits on: the mark, a [title], a
/// [hint] under it, the [fields] on a tinted block, what went wrong, the
/// main button and [extras] under it, such as 返回.
class LockForm extends StatelessWidget {
  const LockForm({
    super.key,
    required this.title,
    required this.hint,
    required this.fields,
    required this.action,
    required this.busy,
    required this.onSubmit,
    this.problem,
    this.waiting,
    this.extras = const [],
    this.actionKey,
  });

  /// Said in place of [problem] while the form may not be sent: the wait
  /// after too many wrong tries. The main button is off meanwhile.
  final String? waiting;

  final String title;
  final String hint;
  final List<Widget> fields;

  /// The main button's words, such as 打開.
  final String action;

  /// Working: the button shows a spinner and nothing can be tapped.
  final bool busy;
  final VoidCallback onSubmit;
  final String? problem;
  final List<Widget> extras;

  /// The main button's key, for tests.
  final Key? actionKey;

  @override
  Widget build(BuildContext context) {
    return LockPage(
      children: [
        const Center(child: AppMark(size: 72)),
        const SizedBox(height: Space.s4),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: TextSize.large,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: Space.s2),
        Text(hint, textAlign: TextAlign.center, style: mutedText),
        const SizedBox(height: Space.s5),
        Container(
          padding: const EdgeInsets.all(Space.s4),
          decoration: BoxDecoration(
            color: AppColors.hero,
            borderRadius: BorderRadius.circular(Radii.largeIncreased),
          ),
          child: Column(
            children: [
              for (final (i, field) in fields.indexed) ...[
                if (i > 0) const SizedBox(height: Space.s2),
                field,
              ],
            ],
          ),
        ),
        if (waiting case final waiting?)
          ProblemLine(waiting, key: Keys.unlockWait)
        else
          ProblemLine(problem),
        const SizedBox(height: Space.s4),
        FilledButton(
          key: actionKey,
          onPressed: busy || waiting != null ? null : onSubmit,
          style: solidButton(
            AppColors.accent,
            minimumSize: Size.fromHeight(48),
            radius: Radii.large,
          ),
          child: busy ? const BusyMark() : Text(action),
        ),
        ...extras,
      ],
    );
  }
}

/// A lock screen page: the paper, centred and no wider than 420, and
/// scrolling when the keyboard or large text needs it.
class LockPage extends StatelessWidget {
  const LockPage({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Space.s6),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// What went wrong, in the danger colour under the fields, with 匯出診斷
/// under it when it sends the person to the diagnostics
/// ([DiagnosticsButton]); nothing when [problem] is null or empty.
class ProblemLine extends StatelessWidget {
  const ProblemLine(this.problem, {super.key});

  final String? problem;

  @override
  Widget build(BuildContext context) {
    final text = problem;
    if (text == null || text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: Space.s2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(text, textAlign: TextAlign.center, style: dangerText),
          Center(child: DiagnosticsButton(text)),
        ],
      ),
    );
  }
}

/// The small spinner a main button shows while working.
class BusyMark extends StatelessWidget {
  const BusyMark({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox.square(
      dimension: 20,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        color: AppColors.onAccent,
      ),
    );
  }
}

/// A quiet button under a lock form, such as 返回; greyed out while
/// [busy].
class LockLink extends StatelessWidget {
  const LockLink(this.label, this.onPressed, {super.key, this.busy = false});

  final String label;
  final VoidCallback onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return TextButton(onPressed: busy ? null : onPressed, child: Text(label));
  }
}

/// How long the opening animation takes: the mark comes in, its bars
/// grow one after another and the arrow is drawn.
// Exception to the motion scale: the opening is played whole, not a change
// from one state to another.
const splashTime = Duration(milliseconds: 1400);

/// The mark as the opening animation draws it, [t] from 0 to 1 over
/// [splashTime].
class OpeningMark extends StatelessWidget {
  const OpeningMark({super.key, required this.t, this.size = 112});

  final double t;
  final double size;

  static double _part(double t, double from, double to, Curve curve) =>
      curve.transform(((t - from) / (to - from)).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    final tile = _part(t, 0, 0.23, Curves.easeOutCubic);
    double bar(int i) =>
        _part(t, 0.16 + 0.086 * i, 0.46 + 0.086 * i, Curves.easeOutBack);
    return Opacity(
      opacity: tile,
      child: Transform.scale(
        scale: 0.7 + 0.3 * tile,
        child: AppMark(
          size: size,
          bars: (bar(0), bar(1), bar(2)),
          arrow: _part(t, 0.57, 0.96, Curves.easeOut),
        ),
      ),
    );
  }
}

/// Runs the opening animation once, from the first frame on the screen
/// (the phone's own start screen shows only the paper colour, so there is
/// nothing to wait out), at once when the phone asks for less motion, and
/// calls `onDone` when it has played.
mixin OpeningAnimation<T extends StatefulWidget>
    on State<T>, TickerProviderStateMixin<T> {
  // Exception to motion: the splash is skipped while motion is off.
  late final opening = AnimationController(vsync: this, duration: splashTime)
    ..addStatusListener((status) {
      if (status == AnimationStatus.completed) openingDone();
    });

  var _started = false;

  /// Called once the mark is fully drawn.
  void openingDone() {}

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (opening.isAnimating || opening.isCompleted) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      // After this frame: what follows the animation may change the
      // screens above this one.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) opening.value = 1;
      });
    } else if (!_started) {
      _started = true;
      // Once the first frame is drawn, so the start is seen.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !opening.isCompleted) unawaited(opening.forward());
      });
    }
  }

  @override
  void dispose() {
    opening.dispose();
    super.dispose();
  }
}

/// The opening animation on the paper colour of the app, while a ledger
/// without a password opens; [onDone] once it has played.
class LockSplash extends StatefulWidget {
  const LockSplash({super.key, this.onDone});

  final VoidCallback? onDone;

  @override
  State<LockSplash> createState() => _LockSplashState();
}

class _LockSplashState extends State<LockSplash>
    with TickerProviderStateMixin, OpeningAnimation {
  @override
  void openingDone() => widget.onDone?.call();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: Center(
        child: Semantics(
          label: '記帳本',
          child: AnimatedBuilder(
            animation: opening,
            builder: (context, _) => OpeningMark(t: opening.value),
          ),
        ),
      ),
    );
  }
}
