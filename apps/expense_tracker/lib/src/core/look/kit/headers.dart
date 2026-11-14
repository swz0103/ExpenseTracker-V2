import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../glyphs.dart';
import '../theme.dart';
import 'words.dart';

// Title rows: a sub-page's centred one, small headings and section spacing.

/// A small heading with a thin rule running to the right: 報表與投資 ——.
class RuleHead extends StatelessWidget {
  const RuleHead(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 10),
      child: Row(
        children: [
          Semantics(
            header: true,
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Hue.muted,
              ),
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(child: Divider(height: 1, color: Hue.line)),
          if (trailing != null) ...[const SizedBox(width: 10), trailing!],
        ],
      ),
    );
  }
}

/// A sub-page's title row: back on the left, the title in the middle and
/// up to two buttons on the right.
class CenterHeader extends StatelessWidget {
  const CenterHeader(
    this.title, {
    super.key,
    required this.onBack,
    this.actions = const [],
  });

  final String title;
  final VoidCallback onBack;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 60),
      margin: const EdgeInsets.only(top: 6),
      child: _HeaderRow(
        children: [
          IconButton(
            tooltip: '返回',
            onPressed: onBack,
            icon: const GlyphIcon(Glyph.back, size: 24),
          ),
          Semantics(
            header: true,
            child: OneLine(
              title,
              alignment: Alignment.center,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
          ),
          Row(mainAxisSize: MainAxisSize.min, children: actions),
        ],
      ),
    );
  }
}

/// Back, title, buttons: the title in the middle of the page between
/// equal sides, as wide as the wider of back and the buttons, so it stays
/// centred and never runs under a button; as tall as the tallest.
class _HeaderRow extends MultiChildRenderObjectWidget {
  const _HeaderRow({required super.children});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderHeaderRow();
}

class _HeaderParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderHeaderRow extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _HeaderParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _HeaderParentData> {
  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _HeaderParentData) {
      child.parentData = _HeaderParentData();
    }
  }

  @override
  void performLayout() {
    final width = constraints.maxWidth;
    final back = firstChild!;
    final title = childAfter(back)!;
    final actions = childAfter(title)!;
    final loose = BoxConstraints(maxWidth: width * 0.4);
    back.layout(loose, parentUsesSize: true);
    actions.layout(loose, parentUsesSize: true);
    final side = [
      back.size.width,
      actions.size.width,
      48.0,
    ].reduce((a, b) => a > b ? a : b);
    title.layout(
      BoxConstraints(maxWidth: (width - side * 2).clamp(0, width)),
      parentUsesSize: true,
    );
    final height = constraints.constrainHeight(
      [
        back.size.height,
        title.size.height,
        actions.size.height,
      ].reduce((a, b) => a > b ? a : b),
    );
    size = Size(width, height);
    void place(RenderBox child, double x) =>
        (child.parentData! as _HeaderParentData).offset = Offset(
          x,
          (height - child.size.height) / 2,
        );
    place(back, 0);
    place(title, (width - title.size.width) / 2);
    place(actions, width - actions.size.width);
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

/// A round icon button for a header's right side, such as ＋ or ⋯.
class HeaderButton extends StatelessWidget {
  const HeaderButton({
    super.key,
    required this.glyph,
    required this.label,
    required this.onTap,
  });

  final Glyph glyph;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: label,
    onPressed: onTap,
    icon: GlyphIcon(glyph, size: 24),
  );
}

/// The blocks of a page with one gap between each, so a page keeps one
/// rhythm: no block runs into the next, and none sits far off. A block is
/// a title with what it heads, or one card; empty ones are left out.
class Sections extends StatelessWidget {
  const Sections(this.children, {super.key, this.gap = 16});

  final List<Widget?> children;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final shown = [for (final c in children) ?c];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, child) in shown.indexed) ...[
          if (i > 0) SizedBox(height: gap),
          child,
        ],
      ],
    );
  }
}

/// A block of [Sections]: its title over what it heads, or null when it
/// heads nothing, so the block is left out.
Widget? section(String? title, List<Widget> body, {Widget? trailing}) {
  if (body.isEmpty) return null;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (title != null) TitleRow(title, trailing: trailing),
      ...body,
    ],
  );
}

/// A block's title in 17 px with something small on the right; the same
/// space under it everywhere.
class TitleRow extends StatelessWidget {
  const TitleRow(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 4,
        children: [
          Semantics(
            header: true,
            child: Text(
              title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
