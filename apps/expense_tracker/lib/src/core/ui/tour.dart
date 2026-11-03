import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../look/app_mark.dart';
import '../look/glyphs.dart';

/// One stop of a [Tour]: the place it lights and what it says there.
final class TourStop {
  const TourStop({
    required this.target,
    required this.title,
    this.round = false,
    this.pad = 8,
  });

  /// The widget to light, found by its key once laid out.
  final GlobalKey target;

  /// The one line said there; a \n breaks it where it reads best.
  final String title;

  /// Lit by a circle, for a button; a rounded box otherwise.
  final bool round;

  /// Room around the widget inside the light.
  final double pad;
}

/// A short walk through the app's main places, over the whole screen: it
/// dims, a light moves from one place to the next with a ring spreading
/// from it, and a card beside the light, tinted like 總覽's main tile with
/// the app's mark, says in one line what that place is for. 下一步 goes on
/// and the last stop's 開始 ends it, as do 略過 and back.
class Tour extends StatefulWidget {
  const Tour({super.key, required this.stops, required this.onDone});

  final List<TourStop> stops;
  final VoidCallback onDone;

  @override
  State<Tour> createState() => _TourState();
}

class _TourState extends State<Tour> with TickerProviderStateMixin {
  var _index = 0;
  var _done = false;

  /// The places have been found and the tour has come in.
  var _shown = false;
  RRect? _from;
  RRect? _to;

  /// The whole tour coming in and going away.
  late final _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );

  /// The light moving to the next stop.
  late final _move = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 480),
  );

  /// The ring spreading from the light, twice at each stop.
  late final _ring = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  /// Spreads the ring twice; it ends at its widest, where it is clear.
  void _pulse() {
    if (_still) return;
    _ring
      ..value = 0
      ..repeat(count: 2);
  }

  Timer? _begin;

  bool get _still => MediaQuery.disableAnimationsOf(context);

  @override
  void initState() {
    super.initState();
    // After the page under it has come in, so the places stand still.
    _begin = Timer(const Duration(milliseconds: 360), () {
      if (!mounted) return;
      setState(() {
        _from = _to = _hole(0);
        _shown = true;
      });
      if (_still) {
        _fade.value = 1;
      } else {
        _fade.forward();
      }
      _pulse();
    });
  }

  @override
  void dispose() {
    _begin?.cancel();
    _fade.dispose();
    _move.dispose();
    _ring.dispose();
    super.dispose();
  }

  /// Where stop [i]'s light goes, in this overlay; null while its widget
  /// is not on screen.
  RRect? _hole(int i) {
    final stop = widget.stops[i];
    final target = stop.target.currentContext?.findRenderObject();
    final overlay = context.findRenderObject();
    if (target is! RenderBox || overlay is! RenderBox) return null;
    if (!target.attached || !target.hasSize) return null;
    final at = overlay.globalToLocal(target.localToGlobal(Offset.zero));
    final box = (at & target.size).inflate(stop.pad);
    if (!stop.round) {
      return RRect.fromRectAndRadius(box, const Radius.circular(22));
    }
    final side = math.max(box.width, box.height);
    return RRect.fromRectAndRadius(
      Rect.fromCenter(center: box.center, width: side, height: side),
      Radius.circular(side / 2),
    );
  }

  double get _t => Curves.easeInOutCubic.transform(_move.value);

  RRect? get _light {
    final from = _from, to = _to;
    if (from == null || to == null) return to ?? from;
    return RRect.lerp(from, to, _t);
  }

  void _next() {
    if (_index == widget.stops.length - 1) {
      unawaited(_finish());
      return;
    }
    final here = _light;
    setState(() {
      _index++;
      _from = here;
      _to = _hole(_index) ?? here;
    });
    if (_still) {
      _move.value = 1;
    } else {
      _move.forward(from: 0);
    }
    _pulse();
  }

  Future<void> _finish() async {
    if (_done) return;
    _done = true;
    if (!_still) await _fade.reverse();
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (popped, _) {
        if (!popped) unawaited(_finish());
      },
      child: FadeTransition(
        opacity: _fade,
        child: LayoutBuilder(
          builder: (context, box) => AnimatedBuilder(
            animation: Listenable.merge([_move, _ring]),
            builder: (context, _) => _layer(box.biggest),
          ),
        ),
      ),
    );
  }

  Widget _layer(Size screen) {
    final light = _light;
    // The card fades out at the old place and in at the new one, rather
    // than sliding across the light.
    final moving = _move.isAnimating;
    final settled = !moving || _t >= 0.5;
    final opacity = moving ? (2 * _t - 1).abs() : 1.0;
    final cardAt = settled ? _to : _from;
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {},
            child: CustomPaint(
              painter: _Dim(light, moving ? 0 : _ring.value),
            ),
          ),
        ),
        if (_shown)
          _placed(
            cardAt,
            screen,
            Opacity(
              opacity: opacity,
              child: _Card(
                // A new stop's card comes up into place.
                key: ValueKey(settled ? _index : _index - 1),
                index: settled ? _index : _index - 1,
                count: widget.stops.length,
                title: widget.stops[settled ? _index : _index - 1].title,
                still: _still,
                onSkip: () => unawaited(_finish()),
                onNext: _next,
              ),
            ),
          ),
      ],
    );
  }

  /// [card] under the light when the light is in the upper half of the
  /// screen, above it otherwise; low in the middle when the place could
  /// not be found.
  Widget _placed(RRect? light, Size screen, Widget card) {
    final under = light != null && light.center.dy < screen.height / 2;
    return Positioned(
      left: 16,
      right: 16,
      top: under ? light.bottom + 14 : null,
      bottom: under
          ? null
          : light == null
          ? screen.height * 0.3
          : screen.height - light.top + 14,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: card,
        ),
      ),
    );
  }
}

/// A stop's card: tinted like 總覽's main tile, the app's mark and
/// 記帳本 · 1 / 3 at the top, the line in large type, then where the tour
/// is, 略過 and a white 下一步 (開始 at the last stop).
class _Card extends StatelessWidget {
  const _Card({
    super.key,
    required this.index,
    required this.count,
    required this.title,
    required this.still,
    required this.onSkip,
    required this.onNext,
  });

  final int index;
  final int count;
  final String title;
  final bool still;
  final VoidCallback onSkip;
  final VoidCallback onNext;

  /// The tile's two tints, the same in dark mode as in light: the card
  /// stands on the dimmed screen, not on the page.
  static const _top = Color(0xFFE6EDEE);
  static const _foot = Color(0xFFD3DEE0);
  static const _ink = Color(0xFF26323A);
  static const _accent = Color(0xFF35657A);
  static const _muted = Color(0xFF525D63);

  @override
  Widget build(BuildContext context) {
    final last = index == count - 1;
    final card = Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_top, _foot],
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x47000000),
            blurRadius: 36,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: const AppMark(size: 30),
              ),
              const SizedBox(width: 10),
              Text(
                '記帳本 · ${index + 1} / $count',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: _accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              height: 1.35,
              color: _ink,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              for (var i = 0; i < count; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 240),
                  margin: const EdgeInsets.only(right: 5),
                  width: i == index ? 16 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: i == index ? _accent : const Color(0x4035657A),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              const Spacer(),
              if (!last)
                TextButton(
                  onPressed: onSkip,
                  style: TextButton.styleFrom(foregroundColor: _muted),
                  child: const Text('略過'),
                ),
              const SizedBox(width: 4),
              FilledButton(
                onPressed: onNext,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFFFFFFF),
                  foregroundColor: _accent,
                  elevation: 0,
                  shape: const StadiumBorder(),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      last ? '開始' : '下一步',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    if (!last) ...[
                      const SizedBox(width: 4),
                      const GlyphIcon(Glyph.arrow, size: 16, color: _accent),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
    final framed = Semantics(liveRegion: true, child: card);
    if (still) return framed;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, 8 * (1 - t)), child: child),
      ),
      child: framed,
    );
  }
}

/// The dimmed screen with the light cut out of it.
class _Dim extends CustomPainter {
  const _Dim(this.light, this.ring);

  final RRect? light;

  /// How far the ring has spread from the light, 0 to 1; none at 0.
  final double ring;

  static const _shade = Color(0xA30C1216);

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size);
    final hole = light;
    if (hole != null) path.addRRect(hole);
    canvas.drawPath(path, Paint()..color = _shade);
    if (hole == null || ring <= 0) return;
    final grow = 4 + 12 * Curves.easeOut.transform(ring);
    canvas.drawRRect(
      hole.inflate(grow),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Color.fromRGBO(255, 255, 255, 0.55 * (1 - ring)),
    );
  }

  @override
  bool shouldRepaint(_Dim oldDelegate) =>
      oldDelegate.light != light || oldDelegate.ring != ring;
}
