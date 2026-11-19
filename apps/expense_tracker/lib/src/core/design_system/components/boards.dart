import 'package:flutter/material.dart';

import '../glyphs.dart';
import '../theme.dart';
import '../components.dart';
import '../shape.dart';
import '../spacing.dart';

// The grey board of rows, the ⋯ menu and what a page shows when empty.

/// The grey board of rows, as on a quote board: each row an icon, a name
/// with one line under it, and a figure on the right, thin rules between.
class QuoteBoard extends StatelessWidget {
  const QuoteBoard(this.rows, {super.key});

  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Hue.group,
        borderRadius: BorderRadius.circular(Radii.largeIncreased),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          children: [
            for (final (i, row) in rows.indexed) ...[
              if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
              row,
            ],
          ],
        ),
      ),
    );
  }
}

/// One row of a [QuoteBoard].
class QuoteRow extends StatelessWidget {
  const QuoteRow({
    super.key,
    required this.title,
    this.lead,
    this.detail,
    this.trailing,
    this.onTap,
  });

  final Widget? lead;
  final String title;
  final String? detail;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final words = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        OneLine(
          title,
          style: const TextStyle(
            fontSize: TextSize.title,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (detail != null)
          Padding(
            padding: const EdgeInsets.only(top: Space.half),
            child: OneLine(detail!, style: mutedSmall),
          ),
      ],
    );
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.s4,
            vertical: Space.s3,
          ),
          child: Row(
            children: [
              if (lead != null) ...[lead!, const SizedBox(width: Space.s4)],
              Expanded(child: words),
              if (trailing != null) ...[
                const SizedBox(width: Space.s2),
                trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A big figure on the right of a [QuoteRow].
class RowFigure extends StatelessWidget {
  const RowFigure(this.text, {super.key, this.color = Hue.ink});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      fontSize: TextSize.title,
      fontWeight: FontWeight.w800,
      color: color,
      fontFeatures: const [FontFeature.tabularFigures()],
    ),
  );
}

/// One choice of a [DotsMenu].
class DotsItem {
  const DotsItem(this.glyph, this.label, this.onTap, {this.danger = false});

  final Glyph glyph;
  final String label;
  final VoidCallback onTap;
  final bool danger;
}

/// The ⋯ in a card's corner, opening a small menu of what can be done to
/// it, the one that cannot be taken back in red at the end.
class DotsMenu extends StatelessWidget {
  const DotsMenu(this.items, {super.key, this.label = '更多選項'});

  final List<DotsItem> items;
  final String label;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      tooltip: label,
      color: Hue.white,
      elevation: 8,
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.large),
      ),
      onSelected: (i) => items[i].onTap(),
      itemBuilder: (context) => [
        for (final (i, item) in items.indexed) ...[
          if (i > 0) const PopupMenuDivider(height: 1),
          PopupMenuItem<int>(
            value: i,
            height: 52,
            child: Row(
              children: [
                GlyphIcon(
                  item.glyph,
                  size: 20,
                  tinted: false,
                  color: item.danger ? Hue.danger : Hue.ink,
                ),
                const SizedBox(width: Space.s4),
                Text(
                  item.label,
                  style: TextStyle(
                    fontSize: TextSize.title,
                    fontWeight: FontWeight.w700,
                    color: item.danger ? Hue.danger : Hue.ink,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: const Color(0x33FFFFFF),
          borderRadius: BorderRadius.circular(Radii.medium),
        ),
        alignment: Alignment.center,
        child: const GlyphIcon(Glyph.more, size: 22, color: Hue.ink),
      ),
    );
  }
}

/// What a page shows with nothing on it yet: a big pale icon in the
/// page's colour, one sentence, and a button when something can be added
/// from here.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.glyph,
    required this.color,
    required this.message,
    this.action,
    this.onAction,
  });

  final Glyph glyph;
  final Color color;
  final String message;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final act = onAction;
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: Space.s8,
        horizontal: Space.s3,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: tintOf(color, 0.22),
              borderRadius: BorderRadius.circular(Radii.extraLarge),
            ),
            alignment: Alignment.center,
            child: GlyphIcon(
              glyph,
              size: 48,
              color: Color.lerp(tintOf(color, 0.22), color, 0.7),
            ),
          ),
          const SizedBox(height: Space.s4),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: TextSize.body, color: Hue.muted),
          ),
          if (action != null && act != null) ...[
            const SizedBox(height: Space.s4),
            FilledButton(
              onPressed: act,
              style: FilledButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Hue.onAccent,
                minimumSize: const Size(0, 52),
                padding: const EdgeInsets.symmetric(horizontal: Space.s6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(Radii.large),
                ),
                textStyle: appFont.copyWith(
                  fontSize: TextSize.title,
                  fontWeight: FontWeight.w800,
                ),
              ),
              child: Text(action!),
            ),
          ],
        ],
      ),
    );
  }
}
