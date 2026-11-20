import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

// The layout that keeps the entry form one height from tab to tab.

/// The form's fields one under another, stretched to the width, and at
/// least [minHeight] tall: height to spare goes above and below the child
/// at [grow], such as the amount, so the form keeps one size from tab to
/// tab with nothing left empty at its foot. Its own height without the
/// spare is told to [onHeight].
class FillLayout extends MultiChildRenderObjectWidget {
  const FillLayout({
    super.key,
    required this.minHeight,
    required this.grow,
    required this.onHeight,
    required super.children,
  });

  final double minHeight;
  final int grow;
  final ValueChanged<double> onHeight;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderFillLayout(minHeight, grow, onHeight);

  @override
  void updateRenderObject(BuildContext context, RenderFillLayout renderObject) {
    renderObject
      ..minHeight = minHeight
      ..grow = grow
      ..onHeight = onHeight;
  }
}

class FillLayoutParentData extends ContainerBoxParentData<RenderBox> {}

class RenderFillLayout extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, FillLayoutParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, FillLayoutParentData> {
  RenderFillLayout(this._minHeight, this._grow, this.onHeight);

  double _minHeight;
  set minHeight(double value) {
    if (value == _minHeight) return;
    _minHeight = value;
    markNeedsLayout();
  }

  int _grow;
  set grow(int value) {
    if (value == _grow) return;
    _grow = value;
    markNeedsLayout();
  }

  ValueChanged<double> onHeight;
  double? _told;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! FillLayoutParentData) {
      child.parentData = FillLayoutParentData();
    }
  }

  @override
  void performLayout() {
    final width = constraints.maxWidth;
    final inner = BoxConstraints.tightFor(width: width);
    var natural = 0.0;
    var child = firstChild;
    while (child != null) {
      child.layout(inner, parentUsesSize: true);
      natural += child.size.height;
      child = childAfter(child);
    }
    final height = constraints.constrainHeight(math.max(natural, _minHeight));
    final spare = math.max(0.0, height - natural);
    var y = 0.0;
    var i = 0;
    child = firstChild;
    while (child != null) {
      if (i == _grow) y += spare / 2;
      (child.parentData! as FillLayoutParentData).offset = Offset(0, y);
      y += child.size.height;
      if (i == _grow) y += spare / 2;
      i++;
      child = childAfter(child);
    }
    size = constraints.constrain(Size(width, height));
    if (_told != natural) {
      _told = natural;
      final told = natural;
      WidgetsBinding.instance.addPostFrameCallback((_) => onHeight(told));
    }
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    final inner = BoxConstraints.tightFor(width: constraints.maxWidth);
    var natural = 0.0;
    var child = firstChild;
    while (child != null) {
      natural += child.getDryLayout(inner).height;
      child = childAfter(child);
    }
    return constraints.constrain(
      Size(constraints.maxWidth, math.max(natural, _minHeight)),
    );
  }

  @override
  double computeMinIntrinsicHeight(double width) {
    var sum = 0.0;
    var child = firstChild;
    while (child != null) {
      sum += child.getMinIntrinsicHeight(width);
      child = childAfter(child);
    }
    return math.max(sum, _minHeight);
  }

  @override
  double computeMaxIntrinsicHeight(double width) =>
      computeMinIntrinsicHeight(width);

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
