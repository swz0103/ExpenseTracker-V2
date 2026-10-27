import 'package:flutter/material.dart';

import '../../../../core/look/app_mark.dart';
import '../../../../core/look/theme.dart';

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
    this.extras = const [],
  });

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

  @override
  Widget build(BuildContext context) {
    return LockPage(
      children: [
        const Center(child: AppMark(size: 72)),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          hint,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Hue.muted),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Hue.hero,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            children: [
              for (final (i, field) in fields.indexed) ...[
                if (i > 0) const SizedBox(height: 8),
                field,
              ],
            ],
          ),
        ),
        ProblemLine(problem),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: busy ? null : onSubmit,
          style: FilledButton.styleFrom(
            backgroundColor: Hue.accent,
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
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
      backgroundColor: Hue.paper,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
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

/// What went wrong, in the danger colour under the fields; nothing when
/// [problem] is null or empty.
class ProblemLine extends StatelessWidget {
  const ProblemLine(this.problem, {super.key});

  final String? problem;

  @override
  Widget build(BuildContext context) {
    final text = problem;
    if (text == null || text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Hue.danger),
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
      child: CircularProgressIndicator(strokeWidth: 2, color: Hue.onAccent),
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

/// The opening animation: the mark grows in and the name fades up, on
/// the paper colour of the app.
class LockSplash extends StatelessWidget {
  const LockSplash({super.key, this.onRestore});

  /// Restoring a backup instead of starting a new ledger; none when the
  /// ledger exists already.
  final VoidCallback? onRestore;

  @override
  Widget build(BuildContext context) {
    final restore = onRestore;
    return Scaffold(
      backgroundColor: Hue.paper,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeOutCubic,
                builder: (context, t, _) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Opacity(
                      opacity: t,
                      child: Transform.scale(
                        scale: 0.8 + 0.2 * t,
                        child: const AppMark(size: 96),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Opacity(
                      opacity: t,
                      child: Transform.translate(
                        offset: Offset(0, 12 * (1 - t)),
                        child: const Text(
                          '記帳本',
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                            color: Hue.ink,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (restore != null)
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: TextButton(
                    onPressed: restore,
                    style: TextButton.styleFrom(foregroundColor: Hue.muted),
                    child: const Text('換手機？從備份還原'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
