import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../look/theme.dart';

/// One stop of a [Tour]: the place it lights and what it says there.
final class TourStop {
  const TourStop({
    required this.target,
    required this.title,
    required this.detail,
    this.round = false,
    this.pad = 8,
  });

  /// The widget to light, found by its key once laid out.
  final GlobalKey target;
  final String title;
  final String detail;

  /// Lit by a circle, for a button; a rounded box otherwise.
  final bool round;

  /// Room around the widget inside the light.
  final double pad;
}

/// A short walk through the app's main places, over the whole screen: it
/// dims, a light moves from one place to the next, and a card beside the
/// light says what that place is for. 下一步 goes on and the last stop's
/// 開始 ends it, as do 略過 and back.
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
    });
  }

  @override
  void dispose() {
    _begin?.cancel();
    _fade.dispose();
    _move.dispose();
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
            animation: _move,
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
            child: CustomPaint(painter: _Dim(light)),
          ),
        ),
        if (_shown)
          _placed(
            cardAt,
            screen,
            Opacity(
              opacity: opacity,
              child: _card(settled ? _index : _index - 1),
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
      top: under ? light!.bottom + 14 : null,
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

  Widget _card(int index) {
    final stop = widget.stops[index];
    final last = index == widget.stops.length - 1;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
        decoration: BoxDecoration(
          color: Hue.panel,
          borderRadius: BorderRadius.circular(18),
          boxShadow: Hue.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              stop.title,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 3),
            Text(stop.detail, style: const TextStyle(color: Hue.muted)),
            const SizedBox(height: 10),
            Row(
              children: [
                for (var i = 0; i < widget.stops.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 240),
                    margin: const EdgeInsets.only(right: 5),
                    width: i == index ? 16 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: i == index ? Hue.accent : Hue.line,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                const Spacer(),
                if (!last)
                  TextButton(
                    onPressed: () => unawaited(_finish()),
                    style: TextButton.styleFrom(foregroundColor: Hue.muted),
                    child: const Text('略過'),
                  ),
                const SizedBox(width: 4),
                FilledButton(
                  onPressed: _next,
                  style: FilledButton.styleFrom(
                    backgroundColor: Hue.accent,
                    foregroundColor: Hue.onAccent,
                    visualDensity: VisualDensity.compact,
                    shape: const StadiumBorder(),
                  ),
                  child: Text(last ? '開始' : '下一步'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The dimmed screen with the light cut out of it.
class _Dim extends CustomPainter {
  const _Dim(this.light);

  final RRect? light;

  static const _shade = Color(0xA30C1216);

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size);
    final hole = light;
    if (hole != null) path.addRRect(hole);
    canvas.drawPath(path, Paint()..color = _shade);
  }

  @override
  bool shouldRepaint(_Dim oldDelegate) => oldDelegate.light != light;
}
