import 'package:flutter/material.dart';

import '../ledger/ledger.dart' show Ledger;
import 'controls.dart';
import 'figures.dart';
import 'glyphs.dart';
import 'haptics.dart';
import 'theme.dart';

/// An icon on a soft square of its own colour.
class IconBadge extends StatelessWidget {
  const IconBadge(
    this.icon,
    this.color, {
    super.key,
    this.size = 40,
    this.filled = false,
  });

  final Glyph icon;
  final Color color;
  final double size;

  /// Solid colour with a light icon, for the chosen option.
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: filled ? color : softOf(color),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: GlyphIcon(
        icon,
        size: size * 0.55,
        color: filled ? Hue.onAccent : color,
      ),
    );
  }
}

/// A rounded panel on the paper.
class SoftPanel extends StatelessWidget {
  const SoftPanel({
    super.key,
    required this.child,
    this.color = Hue.mist,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.lifted,
  });

  final Widget child;
  final Color color;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  /// Whether the panel stands off the paper on [Hue.cardShadow]. When not
  /// given, a white card does and a tinted block does not: [Hue.white],
  /// and [Hue.mist] and [Hue.panel], which are the same object, are
  /// told apart from other colours by identity, not by what their values
  /// happen to be.
  final bool? lifted;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(18);
    final panel = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: (lifted ?? identical(color, Hue.white))
            ? Hue.cardShadow
            : null,
      ),
      child: Material(
        color: color,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
    return onTap == null ? panel : Pressable(depth: 0.985, child: panel);
  }
}

/// An icon in [color] on a small white circle, the mark of a [Tile].
class IconChip extends StatelessWidget {
  const IconChip(
    this.icon, {
    super.key,
    this.size = 28,
    this.color = Hue.accent,
    this.background = const Shade(0xCCFFFFFF, 0x1FFFFFFF),
  });

  final Glyph icon;
  final double size;
  final Color color;

  /// The circle behind the icon: light on tinted blocks, the tint on
  /// white cards.
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: background, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: GlyphIcon(icon, size: size * 0.6, color: color),
    );
  }
}

/// A block of the summary, tinted with the interface colour: a marked
/// label, a figure and a line under it. A [hero] tile is the page's main
/// block, darker and with a larger figure; [child] goes underneath and
/// [lead] to the left of the figure.
class Tile extends StatelessWidget {
  const Tile({
    super.key,
    required this.icon,
    required this.label,
    this.value,
    this.valueColor = Hue.ink,
    this.sub,
    this.trailing,
    this.lead,
    this.child,
    this.hero = false,
    this.size,
    this.onTap,
  });

  final Glyph icon;
  final String label;
  final String? value;
  final Color valueColor;
  final String? sub;
  final Widget? trailing;
  final Widget? lead;
  final Widget? child;
  final bool hero;

  /// The figure's size; 32 on a hero tile, 20 otherwise.
  final double? size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(hero ? 22 : 20);
    final figure = value;
    final note = sub;
    final side = lead;
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (figure != null)
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              figure,
              style: TextStyle(
                fontSize: size ?? (hero ? 32 : 20),
                fontWeight: FontWeight.w700,
                height: 1.2,
                color: valueColor,
              ),
            ),
          ),
        if (note != null)
          Text(
            note,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: mutedSmall,
          ),
      ],
    );
    final tap = onTap;
    final tile = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: Hue.tileShadow,
        gradient: hero
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Shade(0xFFDFE7E8, 0xFF233840), Hue.hero],
              )
            : null,
      ),
      // Two kinds of card in the app: the page's tinted main block, and
      // white cards for everything else.
      child: Material(
        color: hero ? Colors.transparent : Hue.white,
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: tap == null
              ? null
              : () {
                  Haptics.selection();
                  tap();
                },
          child: Padding(
            padding: hero
                ? const EdgeInsets.fromLTRB(16, 14, 16, 14)
                : const EdgeInsets.fromLTRB(13, 12, 13, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    if (hero)
                      IconChip(icon)
                    else
                      IconChip(icon, background: Hue.tile),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: accentLabel,
                      ),
                    ),
                    ?trailing,
                  ],
                ),
                const SizedBox(height: 8),
                if (side != null)
                  Row(
                    children: [
                      side,
                      const SizedBox(width: 12),
                      Expanded(child: text),
                    ],
                  )
                else
                  text,
                ?child,
              ],
            ),
          ),
        ),
      ),
    );
    return tap == null ? tile : Pressable(child: tile);
  }
}

/// Tiles side by side, as tall as the tallest.
class TileRow extends StatelessWidget {
  const TileRow(this.tiles, {super.key});

  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, tile) in tiles.indexed) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(child: tile),
            ],
          ],
        ),
      ),
    );
  }
}

/// Two or three small figures along the bottom of a hero tile, each with
/// its mark.
class TileStats extends StatelessWidget {
  const TileStats(this.items, {super.key});

  /// Mark, label, figure and its colour.
  final List<(Glyph, String, String, Color)> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.only(top: 12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Hue.accentRule)),
      ),
      child: Row(
        children: [
          for (final (icon, label, value, color) in items)
            Expanded(
              child: Row(
                children: [
                  IconChip(icon, size: 26),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Hue.muted,
                          ),
                        ),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            value,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: color,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// A legend mark, a dot or a short line, with its label.
class LegendKey extends StatelessWidget {
  const LegendKey(this.color, this.label, {super.key, this.line = false});

  final Color color;
  final String label;
  final bool line;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: line ? 12 : 8,
          height: line ? 2.5 : 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: mutedSmall),
      ],
    );
  }
}

/// A small rounded label, such as 「結餘率 66%」.
class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.color = Hue.accent});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Shade(0xB3FFFFFF, 0x1FFFFFFF),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(text, style: TextStyle(fontSize: 12.5, color: color)),
    );
  }
}

/// A share of a whole as a ring with the percentage inside.
class RingGauge extends StatelessWidget {
  const RingGauge({
    super.key,
    required this.share,
    this.size = 52,
    this.color = Hue.accent,
  });

  /// 0 to 1; more than 1 draws a full ring in the spending colour.
  final double share;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(share, share > 1 ? Hue.negative : color),
        child: Center(
          child: Text(
            '${(share * 100).round()}%',
            style: TextStyle(fontSize: size / 4.2, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.share, this.color);

  final double share;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.13;
    final rect = Offset.zero & size;
    final arc = rect.deflate(stroke / 2);
    canvas.drawArc(
      arc,
      0,
      6.2832,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = Hue.accentTrack,
    );
    canvas.drawArc(
      arc,
      -1.5708,
      6.2832 * share.clamp(0.0, 1.0),
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.share != share || old.color != color;
}

/// Two bars on one scale, each a share of the largest: [now] in [color]
/// and under it [then], thinner and grey. This period over the same time
/// last year, or what a lot is worth over what it cost.
class PairBars extends StatelessWidget {
  const PairBars({
    super.key,
    required this.now,
    required this.then,
    required this.color,
    this.thenOpacity = 0.6,
  });

  /// Shares of the largest, 0 to 1; a sliver shows even for nothing.
  final double now;
  final double then;
  final Color color;

  /// How strong the grey of [then] is.
  final double thenOpacity;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _bar(now, color, 7),
        const SizedBox(height: 3),
        _bar(then, Hue.faint.withValues(alpha: thenOpacity), 4),
      ],
    );
  }

  static Widget _bar(double share, Color tint, double height) => ClipRRect(
    borderRadius: BorderRadius.circular(height / 2),
    child: SizedBox(
      height: height,
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: share.clamp(0.02, 1.0),
          child: ColoredBox(color: tint),
        ),
      ),
    ),
  );
}

/// The page's main tile for a stretch of time: what is left of [income]
/// after [expense] as the figure, in ink or in the spending colour when
/// more went out than came in; the two along its foot with [third]
/// beside them; and, with [rate], the share of income kept.
class BalanceHero extends StatelessWidget {
  const BalanceHero({
    super.key,
    required this.ledger,
    required this.icon,
    required this.label,
    required this.income,
    required this.expense,
    required this.third,
    this.rate = true,
    this.size,
  });

  /// Writes the amounts, as dots while they are hidden.
  final Ledger ledger;
  final Glyph icon;
  final String label;
  final int income;
  final int expense;

  /// The third figure along the foot: its mark, label, words and colour.
  final (Glyph, String, String, Color) third;
  final bool rate;

  /// The figure's size; the hero tile's own when null.
  final double? size;

  @override
  Widget build(BuildContext context) {
    final left = income - expense;
    final kept = income == 0 ? 0 : (left * 100 / income).round();
    return Tile(
      hero: true,
      icon: icon,
      label: label,
      value: ledger.money(left),
      valueColor: left < 0 ? Hue.negative : Hue.ink,
      size: size,
      trailing: rate ? Pill('結餘率 $kept%') : null,
      child: TileStats([
        (Glyph.income, '收入', ledger.money(income), Hue.positive),
        (Glyph.payout, '支出', ledger.money(expense), Hue.negative),
        third,
      ]),
    );
  }
}
