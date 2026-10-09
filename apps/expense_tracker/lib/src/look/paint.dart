import 'package:flutter/painting.dart';

/// Canvas text inherits nothing, so name the app's font outright.
const _canvasFont = TextStyle(
  fontFamily: 'Nunito',
  fontFamilyFallback: ['Huninn'],
);

/// Lays out one line of [text] for painting on a canvas.
TextPainter layoutText(String text, TextStyle style, {double? maxWidth}) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: _canvasFont.merge(style)),
    textDirection: TextDirection.ltr,
    maxLines: 1,
    ellipsis: '…',
  );
  painter.layout(maxWidth: maxWidth ?? double.infinity);
  return painter;
}

/// Paints [text] so that its [anchor] point lands on [at]: (0, 0) is the
/// top left of the text, (0.5, 0.5) its centre.
void paintText(
  Canvas canvas,
  String text,
  TextStyle style,
  Offset at, {
  Offset anchor = const Offset(0.5, 0.5),
  double? maxWidth,
}) {
  final painter = layoutText(text, style, maxWidth: maxWidth);
  final size = painter.size;
  final corner = Offset(size.width * anchor.dx, size.height * anchor.dy);
  painter.paint(canvas, at - corner);
  painter.dispose();
}
