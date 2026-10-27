import 'package:flutter/material.dart';

import 'glyphs.dart';
import 'theme.dart';
import 'tiles.dart';

/// A white panel of rows with thin rules between them.
class MenuPanel extends StatelessWidget {
  const MenuPanel(this.items, {super.key});

  final List<Widget> items;

  @override
  Widget build(BuildContext context) => SoftPanel(
    color: Hue.white,
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Column(
      children: [
        for (final (i, item) in items.indexed) ...[
          if (i > 0) const Divider(height: 1, indent: 56, endIndent: 14),
          item,
        ],
      ],
    ),
  );
}

/// One row of a [MenuPanel], as a setting: an icon, its name, a few words on its state, and what a
/// tap does, or a control of its own at the end.
class MenuRow extends StatelessWidget {
  const MenuRow({
    super.key,
    required this.glyph,
    required this.title,
    this.detail,
    this.onTap,
    this.trailing,
    this.color = Hue.ink,
    this.vertical = 8,
  });

  final Glyph glyph;
  final String title;
  final String? detail;
  final VoidCallback? onTap;
  final Widget? trailing;
  final Color color;

  /// Space above and below the row.
  final double vertical;

  @override
  Widget build(BuildContext context) {
    final detail = this.detail;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: vertical),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(
                  color: Hue.tile,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: GlyphIcon(
                  glyph,
                  size: 18,
                  color: color == Hue.ink ? Hue.accent : color,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(fontSize: 15, color: color),
                ),
              ),
              // Expanded, not Flexible: the detail takes its half whatever
              // its length, so the arrows line up down the panel.
              if (detail != null)
                Expanded(
                  child: Text(
                    detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: mutedSmall,
                  ),
                ),
              ?trailing,
              if (trailing == null && onTap != null) ...[
                const SizedBox(width: 4),
                const GlyphIcon(Glyph.next, size: 16, color: Hue.muted),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A tinted block of a form, with an optional heading.
class FormBlock extends StatelessWidget {
  const FormBlock({super.key, this.title, required this.child});

  final String? title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final head = title;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
      decoration: BoxDecoration(
        color: Hue.tile,
        borderRadius: BorderRadius.circular(20),
      ),
      child: head == null
          ? child
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(head, style: accentLabel),
                const SizedBox(height: 8),
                child,
              ],
            ),
    );
  }
}
