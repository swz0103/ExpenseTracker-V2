import 'dart:math';

import 'package:flutter/widgets.dart';

/// The app's own line icons, drawn on a 24-unit grid with one stroke
/// weight so they read as a set. Painted, never loaded as images.
enum Glyph {
  home,
  food,
  travel,
  bag,
  subscription,
  other,
  salary,
  payout,
  dividend,
  income,
  transfer,
  investment,
  cash,
  bank,
  phone,
  card,
  overview,
  records,
  wallet,
  add,
  reports,
  budget,
  recurring,
  categories,
  sliders,
  back,
  next,
  arrow,
  close,
  search,
  download,
  edit,
  calendar,
  note,
  eye,
  eyeOff,
  calculator,
  backspace,
  reset,
}

/// A [Glyph] at [size], in [color] or the surrounding icon colour.
class GlyphIcon extends StatelessWidget {
  const GlyphIcon(
    this.glyph, {
    super.key,
    this.size = 22,
    this.color,
    this.weight = 1.6,
  });

  final Glyph glyph;
  final double size;
  final Color? color;

  /// Stroke width in logical pixels.
  final double weight;

  @override
  Widget build(BuildContext context) {
    final ink = color ?? IconTheme.of(context).color ?? const Color(0xFF344638);
    // Like Icon, keep the drawn size when the parent asks for more room.
    return Center(
      widthFactor: 1,
      heightFactor: 1,
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: GlyphPainter(glyph, ink, weight)),
      ),
    );
  }
}

class GlyphPainter extends CustomPainter {
  const GlyphPainter(this.glyph, this.color, this.weight);

  final Glyph glyph;
  final Color color;
  final double weight;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 24;
    if (scale <= 0) return;
    final line = Path();
    final fill = Path();
    _draw(glyph, line, fill);
    canvas
      ..save()
      ..translate((size.width - 24 * scale) / 2, (size.height - 24 * scale) / 2)
      ..scale(scale)
      ..drawPath(
        line,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = weight / scale
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = color,
      )
      ..drawPath(fill, Paint()..color = color)
      ..restore();
  }

  @override
  bool shouldRepaint(GlyphPainter old) =>
      old.glyph != glyph || old.color != color || old.weight != weight;
}

void _poly(Path p, List<double> xy, {bool close = false}) {
  p.moveTo(xy[0], xy[1]);
  for (var i = 2; i < xy.length; i += 2) {
    p.lineTo(xy[i], xy[i + 1]);
  }
  if (close) p.close();
}

void _box(Path p, double l, double t, double r, double b, double radius) {
  p.addRRect(RRect.fromLTRBR(l, t, r, b, Radius.circular(radius)));
}

void _ring(Path p, double x, double y, double r) {
  p.addOval(Rect.fromCircle(center: Offset(x, y), radius: r));
}

void _arc(Path p, double x, double y, double r, double from, double sweep) {
  p.addArc(
    Rect.fromCircle(center: Offset(x, y), radius: r),
    from * pi / 180,
    sweep * pi / 180,
  );
}

/// An open tray, the base of the income marks.
void _tray(Path p) {
  _poly(p, [4, 13, 4, 19, 20, 19, 20, 13]);
  _poly(p, [4, 14.5, 8.5, 14.5, 9.8, 16.5, 14.2, 16.5, 15.5, 14.5, 20, 14.5]);
}

void _calendar(Path p) {
  _box(p, 4, 5.5, 20, 20, 2.5);
  _poly(p, [4, 10, 20, 10]);
  _poly(p, [8.5, 3.5, 8.5, 7]);
  _poly(p, [15.5, 3.5, 15.5, 7]);
}

void _draw(Glyph glyph, Path p, Path f) {
  switch (glyph) {
    case Glyph.home:
      _poly(p, [3.5, 11, 12, 4, 20.5, 11]);
      _poly(p, [6, 9.5, 6, 20, 18, 20, 18, 9.5]);
      _poly(p, [10, 20, 10, 15, 14, 15, 14, 20]);
    case Glyph.food:
      p.moveTo(4, 12);
      p.lineTo(20, 12);
      _arc(p, 12, 12, 8, 0, 180);
      p.moveTo(10, 9);
      p.quadraticBezierTo(8.6, 7, 10, 5);
      p.moveTo(14, 9);
      p.quadraticBezierTo(12.6, 7, 14, 5);
    case Glyph.travel:
      _box(p, 5, 4, 19, 18, 3);
      _poly(p, [5, 11, 19, 11]);
      _poly(p, [8, 18, 8, 20.5]);
      _poly(p, [16, 18, 16, 20.5]);
      _ring(f, 8.5, 14.5, 1);
      _ring(f, 15.5, 14.5, 1);
    case Glyph.bag:
      _box(p, 5, 8, 19, 20, 2.5);
      p.moveTo(9, 10.5);
      p.lineTo(9, 7);
      _arc(p, 12, 7, 3, 180, 180);
      p.moveTo(15, 7);
      p.lineTo(15, 10.5);
    case Glyph.subscription:
      _calendar(p);
      _poly(p, [9, 15, 11, 17, 15, 13]);
    case Glyph.other:
      _ring(f, 6, 12, 1.4);
      _ring(f, 12, 12, 1.4);
      _ring(f, 18, 12, 1.4);
    case Glyph.salary:
      _tray(p);
      _poly(p, [12, 3.5, 12, 11.5]);
      _poly(p, [8.8, 8.5, 12, 11.7, 15.2, 8.5]);
    case Glyph.payout:
      _tray(p);
      _poly(p, [12, 11.5, 12, 3.5]);
      _poly(p, [8.8, 6.7, 12, 3.5, 15.2, 6.7]);
    case Glyph.income:
      _tray(p);
      _poly(p, [12, 4, 12, 11]);
      _poly(p, [8.5, 7.5, 15.5, 7.5]);
    case Glyph.dividend:
      _ring(p, 12, 15.5, 5);
      _poly(p, [12, 13.5, 12, 17.5]);
      _poly(p, [12, 10.5, 12, 7]);
      p.moveTo(12, 7.5);
      p.quadraticBezierTo(8, 7.8, 7.5, 3.8);
      p.quadraticBezierTo(11.5, 3.8, 12, 7.5);
      p.moveTo(12, 7);
      p.quadraticBezierTo(15, 6.8, 16, 4);
      p.quadraticBezierTo(12.8, 4, 12, 7);
    case Glyph.transfer:
      _poly(p, [5, 8.5, 19, 8.5]);
      _poly(p, [15.5, 5, 19, 8.5, 15.5, 12]);
      _poly(p, [19, 15.5, 5, 15.5]);
      _poly(p, [8.5, 12, 5, 15.5, 8.5, 19]);
    case Glyph.investment:
      _poly(p, [4, 17, 9, 12, 13, 15, 20, 7.5]);
      _poly(p, [15.5, 7.5, 20, 7.5, 20, 12]);
    case Glyph.cash:
      _box(p, 3, 6.5, 21, 17.5, 2.5);
      _ring(p, 12, 12, 2.6);
      _ring(f, 6.5, 12, 0.9);
      _ring(f, 17.5, 12, 0.9);
    case Glyph.bank:
      _poly(p, [3.5, 9.5, 12, 4.5, 20.5, 9.5], close: true);
      _poly(p, [7, 12, 7, 17]);
      _poly(p, [12, 12, 12, 17]);
      _poly(p, [17, 12, 17, 17]);
      _poly(p, [4, 20, 20, 20]);
    case Glyph.phone:
      _box(p, 7, 3, 17, 21, 2.5);
      _poly(p, [10.5, 18, 13.5, 18]);
    case Glyph.card:
      _box(p, 3, 6, 21, 18, 2.5);
      _poly(p, [3, 10, 21, 10]);
      _poly(p, [6.5, 14.5, 10, 14.5]);
    case Glyph.overview:
      _box(p, 4, 4, 10.5, 12, 1.8);
      _box(p, 13.5, 4, 20, 8.5, 1.8);
      _box(p, 13.5, 11.5, 20, 20, 1.8);
      _box(p, 4, 15, 10.5, 20, 1.8);
    case Glyph.records:
      _box(p, 5, 3.5, 19, 20.5, 2.5);
      _poly(p, [8.5, 8.5, 15.5, 8.5]);
      _poly(p, [8.5, 12, 15.5, 12]);
      _poly(p, [8.5, 15.5, 12.5, 15.5]);
    case Glyph.wallet:
      _box(p, 3.5, 6, 20.5, 19.5, 2.5);
      _poly(p, [6, 6, 15, 3.5, 16, 6]);
      _box(p, 14, 10.5, 20.5, 15, 1.6);
      _ring(f, 16.5, 12.75, 0.9);
    case Glyph.add:
      _poly(p, [12, 5, 12, 19]);
      _poly(p, [5, 12, 19, 12]);
    case Glyph.reports:
      _box(p, 5.5, 12, 8.5, 19, 1);
      _box(p, 10.5, 6, 13.5, 19, 1);
      _box(p, 15.5, 9.5, 18.5, 19, 1);
      _poly(p, [3.5, 20.5, 20.5, 20.5]);
    case Glyph.budget:
      _ring(p, 12, 12, 8);
      _poly(p, [12, 4, 12, 12, 18.9, 16]);
    case Glyph.recurring:
      _arc(p, 12, 12, 7, 200, 130);
      _poly(p, [18.4, 4.9, 18.1, 8.5, 14.6, 8.1]);
      _arc(p, 12, 12, 7, 20, 130);
      _poly(p, [5.6, 19.1, 5.9, 15.5, 9.4, 15.9]);
    case Glyph.categories:
      _box(p, 4, 4, 10.5, 10.5, 1.8);
      _box(p, 13.5, 4, 20, 10.5, 1.8);
      _box(p, 4, 13.5, 10.5, 20, 1.8);
      _ring(p, 16.75, 16.75, 3.25);
    case Glyph.sliders:
      _poly(p, [4, 7.5, 6.8, 7.5]);
      _poly(p, [11.2, 7.5, 20, 7.5]);
      _ring(p, 9, 7.5, 2.2);
      _poly(p, [4, 16.5, 12.8, 16.5]);
      _poly(p, [17.2, 16.5, 20, 16.5]);
      _ring(p, 15, 16.5, 2.2);
    case Glyph.back:
      _poly(p, [14.5, 5.5, 8, 12, 14.5, 18.5]);
    case Glyph.next:
      _poly(p, [9.5, 5.5, 16, 12, 9.5, 18.5]);
    case Glyph.arrow:
      _poly(p, [5, 12, 19, 12]);
      _poly(p, [14, 7, 19, 12, 14, 17]);
    case Glyph.close:
      _poly(p, [6.5, 6.5, 17.5, 17.5]);
      _poly(p, [17.5, 6.5, 6.5, 17.5]);
    case Glyph.search:
      _ring(p, 10.5, 10.5, 6);
      _poly(p, [15, 15, 19.5, 19.5]);
    case Glyph.download:
      _poly(p, [12, 4, 12, 14.5]);
      _poly(p, [7.5, 10, 12, 14.5, 16.5, 10]);
      _poly(p, [4.5, 15, 4.5, 19.5, 19.5, 19.5, 19.5, 15]);
    case Glyph.edit:
      _poly(p, [5, 19, 5, 15.5, 15.5, 5, 19, 8.5, 8.5, 19], close: true);
      _poly(p, [13, 7.5, 16.5, 11]);
    case Glyph.calendar:
      _calendar(p);
      _ring(f, 8.5, 14.5, 1);
      _ring(f, 12, 14.5, 1);
      _ring(f, 15.5, 14.5, 1);
    case Glyph.note:
      _poly(p, [5, 7, 19, 7]);
      _poly(p, [5, 12, 19, 12]);
      _poly(p, [5, 17, 13, 17]);
    case Glyph.eye:
      p.moveTo(2.5, 12);
      p.quadraticBezierTo(12, 3, 21.5, 12);
      p.quadraticBezierTo(12, 21, 2.5, 12);
      _ring(p, 12, 12, 3);
    case Glyph.eyeOff:
      p.moveTo(2.5, 12);
      p.quadraticBezierTo(12, 3, 21.5, 12);
      p.quadraticBezierTo(12, 21, 2.5, 12);
      _ring(p, 12, 12, 3);
      _poly(p, [4.5, 4.5, 19.5, 19.5]);
    case Glyph.calculator:
      _box(p, 5, 3, 19, 21, 2.5);
      _box(p, 8, 6, 16, 9.5, 1);
      for (final y in const [13.5, 17.5]) {
        for (final x in const [9.0, 12.0, 15.0]) {
          _ring(f, x, y, 0.9);
        }
      }
    case Glyph.backspace:
      _poly(p, [8.5, 6, 20, 6, 20, 18, 8.5, 18, 3.5, 12], close: true);
      _poly(p, [11.5, 9.5, 16.5, 14.5]);
      _poly(p, [16.5, 9.5, 11.5, 14.5]);
    case Glyph.reset:
      _arc(p, 12, 12, 7, 210, 290);
      _poly(p, [5.5, 4.4, 5.9, 8.5, 9.9, 8]);
  }
}
