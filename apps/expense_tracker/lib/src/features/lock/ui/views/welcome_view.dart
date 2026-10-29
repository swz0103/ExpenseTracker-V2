import 'package:flutter/material.dart';

import '../../../../core/look/glyphs.dart';
import '../../../../core/look/theme.dart';
import 'lock_parts.dart';

/// The first screen of a new ledger: the opening animation, then the mark
/// moves up and two choices come in under the name, a new ledger or a
/// backup. No password is asked for here; one can be set in settings.
class WelcomeView extends StatefulWidget {
  const WelcomeView({
    super.key,
    required this.busy,
    required this.onStart,
    required this.onRestore,
    this.problem,
    this.animate = true,
  });

  final bool busy;
  final VoidCallback onStart;
  final VoidCallback onRestore;

  /// Why the ledger did not start.
  final String? problem;

  /// Plays the opening first; off when coming back from the backup form.
  final bool animate;

  @override
  State<WelcomeView> createState() => _WelcomeViewState();
}

class _WelcomeViewState extends State<WelcomeView>
    with TickerProviderStateMixin, OpeningAnimation {
  /// The mark moving up and the choices coming in, after the opening.
  late final _settle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 620),
  );

  @override
  void initState() {
    super.initState();
    if (!widget.animate) {
      // Settled first, so the finished opening has nothing left to start.
      _settle.value = 1;
      opening.value = 1;
    }
  }

  @override
  void openingDone() {
    if (_settle.isAnimating || _settle.isCompleted) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _settle.value = 1;
    } else {
      _settle.forward();
    }
  }

  @override
  void dispose() {
    _settle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Hue.paper,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) => AnimatedBuilder(
            animation: Listenable.merge([opening, _settle]),
            builder: (context, _) => _layout(box.biggest),
          ),
        ),
      ),
    );
  }

  Widget _layout(Size space) {
    final move = Curves.easeInOutCubic.transform(_settle.value);
    final come = Curves.easeOutCubic.transform(
      ((_settle.value - 0.35) / 0.65).clamp(0.0, 1.0),
    );
    // The mark from the middle, as the opening drew it, to above the name.
    final size = 112 + (72 - 112) * move;
    final restY = (space.height * 0.24).clamp(64.0, 220.0);
    final centreY = space.height / 2 + (restY - space.height / 2) * move;
    return Stack(
      children: [
        Positioned(
          left: (space.width - size) / 2,
          top: centreY - size / 2,
          child: Semantics(
            label: '記帳本',
            child: OpeningMark(t: opening.value, size: size),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: restY + 36 + 18,
          bottom: 0,
          child: IgnorePointer(
            ignoring: come < 1,
            child: Opacity(
              opacity: come,
              child: Transform.translate(
                offset: Offset(0, 16 * (1 - come)),
                child: _choices(),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _choices() {
    final busy = widget.busy;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '記帳本',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 28),
              _Choice(
                glyph: Glyph.add,
                label: '第一次使用',
                primary: true,
                busy: busy,
                onTap: busy ? null : widget.onStart,
              ),
              const SizedBox(height: 12),
              _Choice(
                glyph: Glyph.recurring,
                label: '我有備份',
                primary: false,
                busy: false,
                onTap: busy ? null : widget.onRestore,
              ),
              ProblemLine(widget.problem),
            ],
          ),
        ),
      ),
    );
  }
}

/// One of the two choices: a wide card with its mark, its name and an
/// arrow, the main one in the interface colour.
class _Choice extends StatelessWidget {
  const _Choice({
    required this.glyph,
    required this.label,
    required this.primary,
    required this.busy,
    required this.onTap,
  });

  final Glyph glyph;
  final String label;
  final bool primary;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ink = primary ? Hue.onAccent : Hue.ink;
    return Semantics(
      button: true,
      child: Material(
        color: primary ? Hue.accent : Hue.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: primary ? BorderSide.none : const BorderSide(color: Hue.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: primary ? const Color(0x2EFFFFFF) : Hue.hero,
                  ),
                  alignment: Alignment.center,
                  child: GlyphIcon(
                    glyph,
                    size: 20,
                    weight: 2,
                    color: primary ? Hue.onAccent : Hue.accent,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: ink,
                    ),
                  ),
                ),
                if (busy)
                  SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: ink,
                    ),
                  )
                else
                  GlyphIcon(Glyph.next, size: 16, weight: 2.2, color: ink),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
