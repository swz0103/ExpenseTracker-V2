import 'package:flutter/material.dart';

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
    // Clear room under the status bar before the title; taller when the
    // phone's text is larger.
    return Container(
      constraints: const BoxConstraints(minHeight: 60),
      margin: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          if (back != null)
            IconButton(
              tooltip: '返回',
              onPressed: back,
              icon: const GlyphIcon(Glyph.back, size: 24),
            ),
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
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
    return StepSwitch(
      label: '$year / $m',
      previousLabel: '上個月',
      nextLabel: '下個月',
      onPrevious: () => onChanged(_step(-1)),
      onNext: atEnd ? null : () => onChanged(_step(1)),
    );
  }
}

/// Words between a back and a forward arrow, such as a month, a week or
/// a report's period. Each arrow is a 48 dp button named for a screen
/// reader; one with nothing to do ([onPrevious] or [onNext] null) is
/// greyed out.
class StepSwitch extends StatelessWidget {
  const StepSwitch({
    super.key,
    required this.label,
    required this.previousLabel,
    required this.nextLabel,
    this.onPrevious,
    this.onNext,
    this.onLabelTap,
    this.style = const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
    this.iconSize = 18,
    this.expand = false,
  });

  final String label;

  /// What the arrows are called, such as 上個月 and 下個月.
  final String previousLabel;
  final String nextLabel;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  /// What a tap on the words does, such as choosing a range; none leaves
  /// them as words.
  final VoidCallback? onLabelTap;
  final TextStyle style;
  final double iconSize;

  /// Whether the words take all the room between the arrows; otherwise
  /// the switch is as wide as its parts.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final tap = onLabelTap;
    Widget words = Text(label, textAlign: TextAlign.center, style: style);
    if (tap != null) {
      words = InkWell(
        onTap: tap,
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            child: Center(widthFactor: 1, heightFactor: 1, child: words),
          ),
        ),
      );
    }
    Widget arrow(Glyph glyph, String name, VoidCallback? onPressed) =>
        IconButton(
          tooltip: name,
          onPressed: onPressed,
          icon: GlyphIcon(
            glyph,
            size: iconSize,
            color: onPressed == null ? Hue.faint : Hue.muted,
          ),
        );
    return Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        arrow(Glyph.back, previousLabel, onPrevious),
        if (expand) Expanded(child: words) else words,
        arrow(Glyph.next, nextLabel, onNext),
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
      padding: const EdgeInsets.only(top: 20, bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
