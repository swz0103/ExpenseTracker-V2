import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Words that stay on one line, never broken onto a second, which reads
/// badly and makes a block taller than the ones beside it: shrunk to fit
/// their room down to [least] of their size, and past that cut short with
/// an ellipsis, so they are never too small to read.
class OneLine extends StatelessWidget {
  const OneLine(
    this.text, {
    super.key,
    this.style,
    this.textAlign,
    this.alignment = AlignmentDirectional.centerStart,
    this.least = 0.75,
  });

  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;
  final AlignmentGeometry alignment;
  final double least;

  @override
  Widget build(BuildContext context) {
    return _Fit(
      alignment: alignment.resolve(Directionality.of(context)),
      least: least,
      child: Text(
        text,
        style: style,
        textAlign: textAlign,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _Fit extends SingleChildRenderObjectWidget {
  const _Fit({required this.alignment, required this.least, super.child});

  final Alignment alignment;
  final double least;

  @override
  _RenderFit createRenderObject(BuildContext context) =>
      _RenderFit(alignment, least);

  @override
  void updateRenderObject(BuildContext context, _RenderFit box) {
    box
      ..alignment = alignment
      ..least = least;
  }
}

/// Lays the words out at their full width; when that is wider than the
/// room, scales them down to fit, or, below [least], lays them out in the
/// room to end in an ellipsis.
class _RenderFit extends RenderProxyBox {
  _RenderFit(this._alignment, this._least);

  Alignment _alignment;
  set alignment(Alignment value) {
    if (value == _alignment) return;
    _alignment = value;
    markNeedsLayout();
  }

  double _least;
  set least(double value) {
    if (value == _least) return;
    _least = value;
    markNeedsLayout();
  }

  double _scale = 1;
  Offset _shift = Offset.zero;

  @override
  void performLayout() {
    final child = this.child!;
    _scale = 1;
    final room = constraints.maxWidth;
    final natural = child.getMaxIntrinsicWidth(double.infinity);
    if (!room.isFinite || natural <= room) {
      child.layout(constraints.loosen(), parentUsesSize: true);
      size = constraints.constrain(child.size);
    } else if (room / natural >= _least) {
      _scale = room / natural;
      child.layout(
        BoxConstraints(maxHeight: constraints.maxHeight / _scale),
        parentUsesSize: true,
      );
      size = constraints.constrain(Size(room, child.size.height * _scale));
    } else {
      child.layout(constraints.loosen(), parentUsesSize: true);
      size = constraints.constrain(child.size);
    }
    final drawn = child.size * _scale;
    _shift = _alignment.alongOffset(
      Offset(
        math.max(0, size.width - drawn.width),
        math.max(0, size.height - drawn.height),
      ),
    );
  }

  Matrix4 get _transform =>
      Matrix4.translationValues(_shift.dx, _shift.dy, 0)
        ..scaleByDouble(_scale, _scale, 1, 1);

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    if (_scale == 1) {
      context.paintChild(child, offset + _shift);
    } else {
      layer = context.pushTransform(
        needsCompositing,
        offset,
        _transform,
        (context, offset) => context.paintChild(child, offset),
        oldLayer: layer is TransformLayer ? layer as TransformLayer : null,
      );
    }
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    transform.multiply(_transform);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    return result.addWithPaintTransform(
      transform: _transform,
      position: position,
      hitTest: (result, position) => child!.hitTest(result, position: position),
    );
  }

  @override
  double computeMinIntrinsicWidth(double height) => 0;

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final child = this.child!;
    final natural = child.getMaxIntrinsicWidth(double.infinity);
    final room = constraints.maxWidth;
    if (!room.isFinite || natural <= room) {
      return constraints.constrain(child.getDryLayout(constraints.loosen()));
    }
    final scale = room / natural;
    final full = child.getDryLayout(const BoxConstraints());
    return constraints.constrain(
      scale >= _least
          ? Size(room, full.height * scale)
          : child.getDryLayout(constraints.loosen()),
    );
  }
}
