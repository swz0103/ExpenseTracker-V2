import 'package:flutter/widgets.dart';

/// The app icon drawn in place: a ledger book with a bookmark on deep
/// teal, the same shapes as `tool/app_icon.svg` (its visible 300 units).
class AppMark extends StatelessWidget {
  const AppMark({super.key, this.size = 96});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: const CustomPaint(painter: _MarkPainter()),
  );
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 300);
    const square = Rect.fromLTWH(0, 0, 300, 300);
    canvas.drawRRect(
      RRect.fromRectAndRadius(square, const Radius.circular(66)),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment(-0.2, 1),
          colors: [Color(0xFF447A8F), Color(0xFF244B5C)],
        ).createShader(square),
    );
    const corner = Radius.circular(26);
    canvas.drawRRect(
      RRect.fromLTRBR(62, 44, 244, 276, corner),
      Paint()..color = const Color(0x380E2A36),
    );
    canvas.drawRRect(
      RRect.fromLTRBR(62, 34, 244, 266, corner),
      Paint()..color = const Color(0xFFFBF8F1),
    );
    canvas.drawRRect(
      RRect.fromLTRBAndCorners(
        62,
        34,
        88,
        266,
        topLeft: corner,
        bottomLeft: corner,
      ),
      Paint()..color = const Color(0xFFE6C77A),
    );
    canvas.drawRect(
      const Rect.fromLTWH(86, 34, 7, 232),
      Paint()..color = const Color(0xFFCFA94F),
    );
    canvas.drawPath(
      Path()
        ..moveTo(196, 26)
        ..lineTo(226, 26)
        ..lineTo(226, 100)
        ..lineTo(211, 87)
        ..lineTo(196, 100)
        ..close(),
      Paint()..color = const Color(0xFFC8604A),
    );
    for (final (top, width, color) in const [
      (116.0, 96.0, Color(0xFF3B6C80)),
      (148.0, 70.0, Color(0xFFA9C0C8)),
      (180.0, 84.0, Color(0xFFA9C0C8)),
      (212.0, 54.0, Color(0xFFA9C0C8)),
    ]) {
      canvas.drawRRect(
        RRect.fromLTRBR(
          118,
          top,
          118 + width,
          top + 14,
          const Radius.circular(7),
        ),
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_MarkPainter oldDelegate) => false;
}
