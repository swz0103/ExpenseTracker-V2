import 'package:flutter/material.dart';

import 'theme.dart';

/// Shows the app at phone size on a wide screen: a 390 × 844 screen in a
/// dark bezel, scaled down to fit. On a phone-sized screen the app fills
/// it as usual.
class PhoneFrame extends StatelessWidget {
  const PhoneFrame({super.key, required this.child});

  final Widget child;

  static const screen = Size(390, 844);
  static const _bezel = 10.0;
  static const _statusHeight = 34.0;

  /// Room the app leaves for the status bar and the gesture bar.
  static const _insets = EdgeInsets.only(top: _statusHeight, bottom: 18);

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    if (media.size.width <= 520) return child;
    return ColoredBox(
      color: const Color(0xFFE2E5E1),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: FittedBox(
          child: Container(
            padding: const EdgeInsets.all(_bezel),
            decoration: BoxDecoration(
              color: const Color(0xFF26302A),
              borderRadius: BorderRadius.circular(48),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 30,
                  offset: Offset(0, 12),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(38),
              child: SizedBox.fromSize(
                size: screen,
                child: Stack(
                  children: [
                    MediaQuery(
                      data: media.copyWith(
                        size: screen,
                        padding: _insets,
                        viewPadding: _insets,
                        viewInsets: EdgeInsets.zero,
                      ),
                      child: ColoredBox(color: Hue.paper, child: child),
                    ),
                    const Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      height: _statusHeight,
                      child: IgnorePointer(child: _StatusBar()),
                    ),
                    const Positioned(
                      left: 0,
                      right: 0,
                      bottom: 6,
                      child: IgnorePointer(child: _HomeBar()),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A phone's status bar over the preview: the time on the left, a
/// camera hole in the middle, and Wi-Fi, signal and battery on the right.
class _StatusBar extends StatelessWidget {
  const _StatusBar();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 26),
      child: Row(
        children: [
          Text(
            '9:41',
            // Above the app, so no theme: name the font, no underline.
            style: TextStyle(
              fontFamily: 'Nunito',
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Hue.ink,
              height: 1,
              decoration: TextDecoration.none,
            ),
          ),
          Spacer(),
          SizedBox(
            width: 12,
            height: 12,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Color(0xFF1F2622),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Spacer(),
          CustomPaint(size: Size(62, 14), painter: _StatusIcons()),
        ],
      ),
    );
  }
}

class _StatusIcons extends CustomPainter {
  const _StatusIcons();

  @override
  void paint(Canvas canvas, Size size) {
    final ink = Paint()..color = Hue.ink;
    final line = Paint()
      ..color = Hue.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    final mid = size.height / 2;

    // Wi-Fi: three arcs over a dot.
    const wifi = Offset(8, 12);
    for (final r in const [4.0, 7.5, 11.0]) {
      canvas.drawArc(
        Rect.fromCircle(center: wifi, radius: r),
        -2.36,
        1.57,
        false,
        line,
      );
    }
    canvas.drawCircle(wifi, 1.4, ink);

    // Signal: four rising bars.
    for (var i = 0; i < 4; i++) {
      final h = 4.0 + i * 3;
      canvas.drawRRect(
        RRect.fromLTRBR(
          22 + i * 4.5,
          size.height - h,
          25 + i * 4.5,
          size.height,
          const Radius.circular(1),
        ),
        ink,
      );
    }

    // Battery: a case, its charge and the nub.
    final body = RRect.fromLTRBR(
      42,
      mid - 6,
      size.width - 3,
      mid + 6,
      const Radius.circular(3),
    );
    canvas
      ..drawRRect(
        body,
        Paint()
          ..color = Hue.ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      )
      ..drawRRect(
        RRect.fromLTRBR(
          44,
          mid - 4,
          44 + (body.width - 4) * 0.8,
          mid + 4,
          const Radius.circular(1.5),
        ),
        ink,
      )
      ..drawRRect(
        RRect.fromLTRBR(
          size.width - 2,
          mid - 2.5,
          size.width,
          mid + 2.5,
          const Radius.circular(1),
        ),
        ink,
      );
  }

  @override
  bool shouldRepaint(_StatusIcons old) => false;
}

/// The gesture bar at the foot of the screen.
class _HomeBar extends StatelessWidget {
  const _HomeBar();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 108,
        height: 4,
        decoration: BoxDecoration(
          color: Hue.ink.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}
