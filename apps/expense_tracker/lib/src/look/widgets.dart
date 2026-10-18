import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'glyphs.dart';
import 'theme.dart';

/// A page's title row: an optional back arrow, the title in 22 px and
/// whatever sits on the right.
class PageHeader extends StatelessWidget {
  const PageHeader(this.title, {super.key, this.onBack, this.trailing});

  final String title;
  final VoidCallback? onBack;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final back = onBack;
    // Clear room under the status bar before the title.
    return Container(
      height: 60,
      margin: const EdgeInsets.only(top: 14),
      child: Row(
        children: [
          if (back != null)
            IconButton(
              tooltip: '返回',
              onPressed: back,
              icon: const GlyphIcon(Glyph.back, size: 24),
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
            ),
          Text(
            title,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
          const Spacer(),
          ?trailing,
        ],
      ),
    );
  }
}

/// 「‹ 2026 / 10 ›」.
class MonthSwitch extends StatelessWidget {
  const MonthSwitch({
    super.key,
    required this.month,
    required this.onChanged,
    this.latest,
  });

  final (int, int) month;
  final ValueChanged<(int, int)> onChanged;

  /// The last month that may be chosen.
  final (int, int)? latest;

  (int, int) _step(int by) {
    final date = DateTime.utc(month.$1, month.$2 + by);
    return (date.year, date.month);
  }

  @override
  Widget build(BuildContext context) {
    final (year, m) = month;
    final last = latest;
    final atEnd = last != null && year * 12 + m >= last.$1 * 12 + last.$2;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: '上個月',
          onPressed: () => onChanged(_step(-1)),
          icon: const GlyphIcon(Glyph.back, size: 18, color: Hue.muted),
        ),
        Text(
          '$year / $m',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        IconButton(
          tooltip: '下個月',
          onPressed: atEnd ? null : () => onChanged(_step(1)),
          icon: const GlyphIcon(Glyph.next, size: 18, color: Hue.muted),
        ),
      ],
    );
  }
}

/// A section's title in 17 px with something on the right.
class SectionHead extends StatelessWidget {
  const SectionHead(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 28, bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const Spacer(),
          ?trailing,
        ],
      ),
    );
  }
}

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
        color: filled ? Hue.white : color,
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
  });

  final Widget child;
  final Color color;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(18);
    final panel = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: color == Hue.white ? Hue.cardShadow : null,
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

/// Short feedback at the bottom, with an optional action.
void showNote(
  BuildContext context,
  String message, {
  String? action,
  VoidCallback? onAction,
}) {
  final act = onAction;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        action: action == null || act == null
            ? null
            : SnackBarAction(
                label: action,
                textColor: Hue.selected,
                onPressed: act,
              ),
      ),
    );
}

/// Opens [builder] in a sheet from the bottom of the screen, full width,
/// as tall as its content and lifted over the keyboard. Every form and
/// picker in the app opens this way.
Future<T?> showSheet<T>(BuildContext context, WidgetBuilder builder) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: Hue.panel,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: builder(context),
    ),
  );
}

/// An icon in [color] on a small white circle, the mark of a [Tile].
class IconChip extends StatelessWidget {
  const IconChip(
    this.icon, {
    super.key,
    this.size = 28,
    this.color = Hue.accent,
  });

  final Glyph icon;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: Color(0xCCFFFFFF),
        shape: BoxShape.circle,
      ),
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
            style: const TextStyle(fontSize: 12, color: Hue.muted),
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
                colors: [Color(0xFFD3DEE0), Hue.hero],
              )
            : null,
      ),
      child: Material(
        color: hero ? Colors.transparent : Hue.tile,
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: tap == null
              ? null
              : () {
                  HapticFeedback.selectionClick();
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
                    IconChip(icon),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: Hue.accent,
                        ),
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
        border: Border(top: BorderSide(color: Color(0x2E3B6C80))),
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
                            fontSize: 11,
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
        color: const Color(0xB3FFFFFF),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(text, style: TextStyle(fontSize: 11.5, color: color)),
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
        ..color = const Color(0x263B6C80),
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

/// A row of choices in a tinted track, the chosen one on white.
class Segments extends StatelessWidget {
  const Segments({
    super.key,
    required this.labels,
    required this.selected,
    required this.onChanged,
    this.selectedColor = Hue.accent,
  });

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;
  final Color selectedColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Hue.tile,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          for (final (i, label) in labels.indexed)
            Expanded(
              child: GestureDetector(
                onTap: () {
                  if (i != selected) HapticFeedback.selectionClick();
                  onChanged(i);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: i == selected ? Hue.white : null,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: i == selected
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: i == selected ? selectedColor : Hue.accent,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Sinks a little under the finger and springs back, so a tap is felt as
/// well as seen.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, this.depth = 0.97});

  final Widget child;

  /// How far it shrinks while held.
  final double depth;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  var _down = false;

  void _set(bool down) {
    if (_down != down) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _down ? widget.depth : 1,
        duration: Duration(milliseconds: _down ? 90 : 220),
        curve: _down ? Curves.easeOut : Curves.easeOutBack,
        child: widget.child,
      ),
    );
  }
}
