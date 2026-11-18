import 'package:flutter/material.dart';

import '../../../../core/look/glyphs.dart';
import '../../../../core/look/theme.dart';
import 'lock_parts.dart';
import '../../../../core/look/kit/buttons.dart';
import '../../../../core/look/keys.dart';
import '../../../../core/text/dates.dart';
import '../../../../core/look/spacing.dart';
import '../../../../core/look/shape.dart';

/// The first screen of a new ledger: the opening animation, then the page
/// takes on the tint of 總覽's main tile, the mark rises a little with the
/// name under it, and at the foot 建立新帳本 and, for a new phone,
/// 已經有帳本？還原備份. When Android brought this ledger's backup back
/// ([found]: reinstalled, or a new phone), the foot offers that backup in
/// a pill instead, with 建立新帳本 under it. No password is asked for
/// here; one can be set in settings.
class WelcomeView extends StatefulWidget {
  const WelcomeView({
    super.key,
    required this.busy,
    required this.onStart,
    required this.onRestore,
    this.problem,
    this.animate = true,
    this.found,
    this.onRestoreFound,
  });

  final bool busy;
  final VoidCallback onStart;
  final VoidCallback onRestore;

  /// Why the ledger did not start.
  final String? problem;

  /// Plays the opening first; off when coming back from the backup form.
  final bool animate;

  /// The backup Android brought back: when it was taken and its records.
  final ({DateTime at, int rows})? found;

  /// Restores [found].
  final VoidCallback? onRestoreFound;

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
      body: LayoutBuilder(
        builder: (context, box) => AnimatedBuilder(
          animation: Listenable.merge([opening, _settle]),
          builder: (context, _) => _layout(box.biggest),
        ),
      ),
    );
  }

  /// A soft light behind the mark, on the tinted top of the page.

  Widget _layout(Size space) {
    final move = Curves.easeInOutCubic.transform(_settle.value);
    final come = Curves.easeOutCubic.transform(
      ((_settle.value - 0.35) / 0.65).clamp(0.0, 1.0),
    );
    final inset = MediaQuery.paddingOf(context);
    // The mark from the middle, as the opening drew it, up a little.
    final size = 112 + (104 - 112) * move;
    final restY = (space.height * 0.36).clamp(150.0, 320.0);
    final centreY = space.height / 2 + (restY - space.height / 2) * move;
    return Stack(
      children: [
        Positioned.fill(
          child: Opacity(
            opacity: move,
            child: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Hue.hero, Hue.hero, Hue.paper],
                  stops: [0, 0.45, 0.78],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: space.width / 2 - 100,
          top: restY - 100,
          child: Opacity(
            opacity: move,
            child: Container(
              width: 200,
              height: 200,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [Hue.halo, Hue.none],
                  stops: [0, 0.68],
                ),
              ),
            ),
          ),
        ),
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
          top: restY + 52 + 16,
          child: _rise(
            come,
            const Text(
              '記帳本',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: TextSize.figure,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.8,
              ),
            ),
          ),
        ),
        Positioned(
          left: 24,
          right: 24,
          bottom: inset.bottom + 20,
          child: _rise(come, _choices()),
        ),
      ],
    );
  }

  /// [child] coming up into place as [come] goes from 0 to 1; it takes
  /// no taps until it is there.
  Widget _rise(double come, Widget child) => IgnorePointer(
    ignoring: come < 1,
    child: Opacity(
      opacity: come,
      child: Transform.translate(
        offset: Offset(0, 16 * (1 - come)),
        child: child,
      ),
    ),
  );

  Widget _choices() {
    final busy = widget.busy;
    final found = widget.found;
    if (found != null) return _foundChoices(found, busy);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ProblemLine(widget.problem),
            const SizedBox(height: Space.s3),
            FilledButton(
              key: Keys.newBook,
              onPressed: busy ? null : widget.onStart,
              style: solidButton(
                Hue.accent,
                minimumSize: Size.fromHeight(52),
                radius: Radii.large,
              ),
              child: busy
                  ? const BusyMark()
                  : const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GlyphIcon(
                          Glyph.add,
                          size: 18,
                          weight: 2.2,
                          color: Hue.onAccent,
                        ),
                        SizedBox(width: Space.s2),
                        Text(
                          '建立新帳本',
                          style: TextStyle(
                            fontSize: TextSize.title,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: Space.s2),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('已經有帳本？', style: TextStyle(color: Hue.muted)),
                TextButton(
                  key: Keys.restore,
                  onPressed: busy ? null : widget.onRestore,
                  style: wordButton(
                    Hue.accent,
                    minimumSize: Size(48, 48),
                    padding: const EdgeInsets.symmetric(horizontal: Space.s2),
                  ),
                  child: const Text(
                    '還原備份',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// The backup Android brought back, in a pill: tapped, it asks for its
  /// password or recovery code; 建立新帳本 under it.
  Widget _foundChoices(({DateTime at, int rows}) found, bool busy) {
    final at = found.at.toLocal();
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ProblemLine(widget.problem),
            const SizedBox(height: Space.s3),
            DecoratedBox(
              decoration: const ShapeDecoration(
                shape: StadiumBorder(),
                shadows: [
                  BoxShadow(
                    color: Hue.float,
                    blurRadius: 26,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: Material(
                color: Hue.white,
                shape: const StadiumBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  key: Keys.restoreFound,
                  onTap: busy ? null : widget.onRestoreFound,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Space.s2,
                      Space.s2,
                      Space.s2,
                      Space.s2,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: const BoxDecoration(
                            color: Hue.accentTrack,
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: const GlyphIcon(
                            Glyph.reset,
                            size: 20,
                            color: Hue.accent,
                          ),
                        ),
                        const SizedBox(width: Space.s3),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '還原 ${formatMMMd(at)}的備份',
                                style: const TextStyle(
                                  fontSize: TextSize.body,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                '${_grouped(found.rows)} 筆紀錄',
                                style: const TextStyle(
                                  fontSize: TextSize.caption,
                                  color: Hue.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: Space.s3),
                        Container(
                          width: 48,
                          height: 48,
                          decoration: const BoxDecoration(
                            color: Hue.accent,
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: busy
                              ? const BusyMark()
                              : const GlyphIcon(
                                  Glyph.arrow,
                                  size: 20,
                                  color: Hue.onAccent,
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: Space.s2),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('或', style: TextStyle(color: Hue.muted)),
                TextButton(
                  key: Keys.newBook,
                  onPressed: busy ? null : widget.onStart,
                  style: wordButton(
                    Hue.accent,
                    minimumSize: Size(48, 48),
                    padding: const EdgeInsets.symmetric(horizontal: Space.s2),
                  ),
                  child: const Text(
                    '建立新帳本',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 1234 as 1,234.
  static String _grouped(int n) => n.toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
}
