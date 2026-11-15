part of 'composer.dart';

/// One of 常用 under the amount: a small white pill with a grey mark,
/// its name and amount, a tap from a filled form. [strong] writes the
/// name in ink, for a switch such as 代墊 at the front of the row.
class _UsualChip extends StatelessWidget {
  const _UsualChip({
    required this.icon,
    required this.name,
    required this.onTap,
    this.amount,
    this.strong = false,
  });

  final Glyph icon;
  final String name;
  final String? amount;
  final VoidCallback onTap;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final figure = amount;
    return TapArea(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(5, 5, 12, 5),
        decoration: BoxDecoration(
          color: Hue.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Hue.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: Hue.surface,
                shape: BoxShape.circle,
              ),
              child: GlyphIcon(icon, size: 14, color: Hue.muted),
            ),
            const SizedBox(width: 7),
            Text(
              name,
              maxLines: 1,
              style: TextStyle(
                fontSize: TextSize.small,
                fontWeight: strong ? FontWeight.w700 : FontWeight.w400,
                color: strong ? Hue.ink : Hue.muted,
              ),
            ),
            if (figure != null) ...[
              const SizedBox(width: 6),
              Text(
                figure,
                maxLines: 1,
                style: const TextStyle(
                  fontSize: TextSize.body,
                  fontWeight: FontWeight.w700,
                  color: Hue.ink,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Someone's share of a spending paid partly for them: a pill tinted in
/// [color] with their name and amount, a tap to change it.
class _LentChip extends StatelessWidget {
  const _LentChip({
    required this.name,
    required this.amount,
    required this.color,
    required this.onTap,
  });

  final String name;
  final String amount;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return TapArea(
      onTap: onTap,
      label: '幫$name付 $amount',
      child: Container(
        padding: const EdgeInsets.fromLTRB(5, 5, 12, 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: Hue.white,
                shape: BoxShape.circle,
              ),
              child: GlyphIcon(Glyph.heart, size: 13, color: color),
            ),
            const SizedBox(width: 7),
            Text(
              name,
              maxLines: 1,
              style: TextStyle(
                fontSize: TextSize.small,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              amount,
              maxLines: 1,
              style: TextStyle(
                fontSize: TextSize.body,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 常用 as one row from the left that slides sideways; [lead], such as
/// 代墊, stays first with a thin line after it.
class _UsualRow extends StatelessWidget {
  const _UsualRow(this.children, {this.lead});

  final List<Widget> children;
  final Widget? lead;

  @override
  Widget build(BuildContext context) {
    final first = lead;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          if (first != null) ...[
            first,
            if (children.isNotEmpty)
              Container(
                width: 1,
                height: 22,
                margin: const EdgeInsets.symmetric(horizontal: 8),
                color: Hue.line,
              ),
          ],
          for (final (i, child) in children.indexed) ...[
            if (i > 0) const SizedBox(width: 8),
            child,
          ],
        ],
      ),
    );
  }
}

/// Whom money is paid for or from, under the amount in place of 常用:
/// a tinted pill with the person's name, a tap to change them, and a
/// cross back to a plain entry.
class _PersonPill extends StatelessWidget {
  const _PersonPill({
    required this.text,
    required this.sub,
    required this.color,
    required this.onTap,
    this.onClear,
  });

  final String text;
  final String sub;
  final Color color;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final clear = onClear;
    return Center(
      child: Container(
        padding: EdgeInsets.only(left: 5, right: clear == null ? 12 : 0),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color, width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: TapArea(
                onTap: onTap,
                label: '$text，$sub，換人',
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: Hue.white,
                        shape: BoxShape.circle,
                      ),
                      child: GlyphIcon(Glyph.heart, size: 13, color: color),
                    ),
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: TextSize.small,
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: TextSize.caption,
                          color: Hue.muted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (clear != null)
              IconButton(
                tooltip: '不是代墊',
                onPressed: clear,
                icon: GlyphIcon(Glyph.close, size: 14, color: color),
              ),
          ],
        ),
      ),
    );
  }
}

/// One sum someone still owes, as a card to tick: what it was for, when,
/// and what is left of it; ticked ones are what is being paid back.
class _OwedCard extends StatelessWidget {
  const _OwedCard({
    required this.title,
    required this.when,
    required this.amount,
    required this.picked,
    required this.color,
    required this.onTap,
  });

  final String title;
  final String when;
  final String amount;
  final bool picked;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(16);
    return Semantics(
      button: true,
      selected: picked,
      label: '$title，$when，$amount',
      excludeSemantics: true,
      child: Material(
        color: picked ? color.withValues(alpha: 0.12) : Hue.surface,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: picked ? BorderSide(color: color, width: 1.5) : BorderSide.none,
        ),
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: SizedBox(
            width: 150,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: TextSize.body,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          when,
                          maxLines: 1,
                          style: const TextStyle(
                            fontSize: TextSize.tiny,
                            color: Hue.muted,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          amount,
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: TextSize.title,
                            fontWeight: FontWeight.w700,
                            color: picked ? color : Hue.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 20,
                    height: 20,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: picked ? color : Hue.white,
                      shape: BoxShape.circle,
                    ),
                    child: picked
                        ? const Text(
                            '✓',
                            style: TextStyle(
                              fontSize: TextSize.caption,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          )
                        : null,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A word to pick in a row of them, such as a merchant or a tag: grey,
/// or tinted and ringed in [color] when [picked].
class _WordChip extends StatelessWidget {
  const _WordChip(
    this.label,
    this.onTap, {
    required this.color,
    this.picked = false,
  });

  final String label;
  final VoidCallback onTap;
  final Color color;
  final bool picked;

  @override
  Widget build(BuildContext context) {
    return TapArea(
      onTap: onTap,
      selected: picked,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: picked ? color.withValues(alpha: 0.12) : Hue.surface,
          borderRadius: BorderRadius.circular(12),
          border: picked ? Border.all(color: color, width: 1.5) : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: TextSize.small,
            fontWeight: FontWeight.w700,
            color: picked ? color : Hue.ink,
          ),
        ),
      ),
    );
  }
}

/// Words in a row that slides sideways, such as the merchants.
class _WordRow extends StatelessWidget {
  const _WordRow(this.children);

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (i, child) in children.indexed) ...[
            if (i > 0) const SizedBox(width: 7),
            child,
          ],
        ],
      ),
    );
  }
}

/// A small grey heading over a group of fields, such as 商家.
class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 10, 2, 2),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: TextSize.caption,
          fontWeight: FontWeight.w700,
          color: Hue.muted,
        ),
      ),
    );
  }
}

/// The form's fields one under another, stretched to the width, and at
/// least [minHeight] tall: height to spare goes above and below the child
/// at [grow], such as the amount, so the form keeps one size from tab to
/// tab with nothing left empty at its foot. Its own height without the
/// spare is told to [onHeight].
class _Fill extends MultiChildRenderObjectWidget {
  const _Fill({
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
      _RenderFill(minHeight, grow, onHeight);

  @override
  void updateRenderObject(BuildContext context, _RenderFill renderObject) {
    renderObject
      ..minHeight = minHeight
      ..grow = grow
      ..onHeight = onHeight;
  }
}

class _FillData extends ContainerBoxParentData<RenderBox> {}

class _RenderFill extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _FillData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _FillData> {
  _RenderFill(this._minHeight, this._grow, this.onHeight);

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
    if (child.parentData is! _FillData) child.parentData = _FillData();
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
      (child.parentData! as _FillData).offset = Offset(0, y);
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
