import 'package:flutter/material.dart';

import '../../../../design_system/display/amount.dart';
import '../../../core/design_system/glyphs.dart';
import '../../../core/widgets/icons.dart';
import '../../../core/design_system/theme.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/ledger/ledger.dart';
import '../../../core/widgets/shown_amounts.dart';
import '../../../../design_system/display/date.dart';
import '../../../core/design_system/shape.dart';
import '../../../core/design_system/spacing.dart';
import '../../../core/formatting/words.dart';

export 'merchant_tag_pickers.dart';

// The pieces of the entry form that hold no state of the form: its tabs,
// headers, amount, pickers and the squares in a row of choices.

/// The spending a refund belongs to, at the top of the refund form.
class OriginalEntryTile extends StatelessWidget {
  const OriginalEntryTile({
    super.key,
    required this.ledger,
    required this.entry,
  });

  final Ledger ledger;
  final Entry entry;

  @override
  Widget build(BuildContext context) {
    final currency = ledger.account(entry.account).currency;
    final category = ledger.category(entry.category);
    return Container(
      padding: const EdgeInsets.all(Space.s3),
      decoration: BoxDecoration(
        color: AppColors.tile,
        borderRadius: BorderRadius.circular(Radii.large),
      ),
      child: Row(
        children: [
          RoundIcon(
            iconFor(category.icon),
            shownColor(Color(category.color)),
            size: 36,
          ),
          const SizedBox(width: Space.s2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('原支出 · ${formatMd(entry.date)}', style: mutedSmall),
                Text(
                  entry.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          Text(
            '−${ledger.moneyIn(entry.amount, currency)}',
            semanticsLabel: ledger.spoken(
              entry.amount,
              currency: currency,
              sense: AmountSense.spending,
            ),
            style: const TextStyle(
              fontSize: TextSize.title,
              fontWeight: FontWeight.w700,
              color: AppColors.negative,
            ),
          ),
        ],
      ),
    );
  }
}

/// The kinds of entry along the top, sharing the width; the chosen one
/// in ink over a thick line of its colour, the others faint over a thin
/// one. [onReset] adds 重填 at the end, level with the words.
class EntryTypeTabs extends StatelessWidget {
  const EntryTypeTabs({
    super.key,
    required this.labels,
    required this.selected,
    required this.color,
    required this.onChanged,
    this.onReset,
  });

  final List<String> labels;
  final int selected;
  final Color color;
  final ValueChanged<int> onChanged;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    final reset = onReset;
    Widget cell(Widget child, {required bool on}) => Container(
      height: 48,
      alignment: Alignment.center,
      foregroundDecoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: on ? color : AppColors.line,
            width: on ? 3 : 1,
          ),
        ),
      ),
      child: child,
    );
    return Row(
      children: [
        for (final (i, label) in labels.indexed)
          Expanded(
            child: TapArea(
              selected: i == selected,
              onTap: () => onChanged(i),
              child: cell(
                Text(
                  label,
                  style: TextStyle(
                    fontSize: TextSize.title,
                    fontWeight: FontWeight.w700,
                    color: i == selected ? AppColors.ink : AppColors.faint,
                  ),
                ),
                on: i == selected,
              ),
            ),
          ),
        if (reset != null)
          SizedBox(
            width: 48,
            child: cell(
              IconButton(
                tooltip: '重填',
                onPressed: reset,
                icon: const GlyphIcon(
                  Glyph.reset,
                  size: 20,
                  color: AppColors.faint,
                ),
              ),
              on: false,
            ),
          ),
      ],
    );
  }
}

/// The title of a choice opened inside the sheet, centred, with the
/// arrow back to the form on its left.
class SubpageHeader extends StatelessWidget {
  const SubpageHeader({super.key, required this.title, required this.onBack});

  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: Words.back,
            onPressed: onBack,
            icon: const GlyphIcon(Glyph.back, size: 20, color: AppColors.muted),
          ),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: TextSize.title,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }
}

/// The amount, centred, NT$ small at its foot; the calculator mark on
/// the right opens the keypad, as does a tap on the figure. [label] names
/// it for a screen reader, such as 金額 or 代墊金額. [under] goes below,
/// such as 常用.
class AmountHero extends StatelessWidget {
  const AmountHero({
    super.key,
    required this.label,
    required this.unit,
    required this.value,
    required this.color,
    required this.onTap,
    this.sub,
    this.under,
    this.empty = false,
    this.spoken,
  });

  final String label;
  final String unit;
  final String value;
  final Color color;

  /// Nothing typed yet: the 0 waits in the faint colour of a placeholder,
  /// as the unit beside it, so it is not taken for an amount.
  final bool empty;

  /// What a screen reader says for [value] when it is an amount with a
  /// sign: its direction in words (支出 200 元).
  final String? spoken;
  final VoidCallback? onTap;
  final String? sub;
  final Widget? under;

  @override
  Widget build(BuildContext context) {
    final tap = onTap;
    final note = sub;
    final below = under;
    // Two words with their feet level, so the figure reads on its own.
    // (Aligned to the end rather than to the baseline, which the sheet's
    // fill-the-height layout cannot measure.)
    final figure = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: Space.s2),
          child: Text(
            unit,
            style: const TextStyle(
              fontSize: TextSize.title,
              fontWeight: FontWeight.w700,
              color: AppColors.faint,
            ),
          ),
        ),
        const SizedBox(width: Space.s2),
        Text(
          value,
          maxLines: 1,
          style: TextStyle(
            fontSize: TextSize.hero,
            fontWeight: FontWeight.w700,
            height: 1.1,
            color: empty ? AppColors.faint : color,
          ),
        ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: Space.s4),
        Row(
          children: [
            const SizedBox(width: 48),
            Expanded(
              // Read as its name and the figure, 應付 0, not the unit
              // drawn beside the figure as well.
              child: Semantics(
                button: tap != null,
                label: label,
                value: spoken ?? value,
                onTap: tap,
                excludeSemantics: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: tap,
                  child: FittedBox(fit: BoxFit.scaleDown, child: figure),
                ),
              ),
            ),
            SizedBox(
              width: 48,
              child: tap == null
                  ? null
                  : IconButton(
                      tooltip: label,
                      onPressed: tap,
                      icon: const GlyphIcon(
                        Glyph.calculator,
                        size: 20,
                        color: AppColors.muted,
                      ),
                    ),
            ),
          ],
        ),
        if (note != null)
          Text(note, textAlign: TextAlign.center, style: mutedSmall),
        if (below != null) ...[const SizedBox(height: Space.s3), below],
      ],
    );
  }
}

/// Small rounded words under the amount, such as one of 常用.
class Bubble extends StatelessWidget {
  const Bubble(this.label, this.onTap, {super.key, this.color, this.ink});

  final String label;
  final VoidCallback? onTap;
  final Color? color;
  final Color? ink;

  @override
  Widget build(BuildContext context) {
    return TapArea(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color ?? AppColors.surface,
          borderRadius: BorderRadius.circular(Radii.full),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.s3,
            vertical: Space.s2,
          ),
          child: Text(
            label,
            maxLines: 1,
            style: TextStyle(
              fontSize: TextSize.small,
              fontWeight: FontWeight.w600,
              color: ink ?? AppColors.muted,
            ),
          ),
        ),
      ),
    );
  }
}

/// A row of [Bubble]s, centred, sliding sideways when they do not fit.
class BubbleRow extends StatelessWidget {
  const BubbleRow(this.children, {super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final (i, child) in children.indexed) ...[
              if (i > 0) const SizedBox(width: Space.s2),
              child,
            ],
          ],
        ),
      ),
    );
  }
}

/// One square in a row of choices, such as a category: a grey mark over
/// its name, tinted and ringed in [color] when [picked]; [solid] fills it
/// with [color] instead, such as 拆分中.
class ChoiceStripItem extends StatelessWidget {
  const ChoiceStripItem({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.picked,
    required this.onTap,
    this.solid = false,
  });

  final String label;
  final Glyph icon;
  final Color color;
  final bool picked;
  final VoidCallback? onTap;
  final bool solid;

  @override
  Widget build(BuildContext context) {
    final lit = picked || solid;
    return TapArea(
      onTap: onTap,
      selected: picked,
      child: SizedBox(
        width: 58,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 50,
              height: 50,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: solid
                    ? color
                    : picked
                    ? color.withValues(alpha: 0.14)
                    : AppColors.surface,
                borderRadius: BorderRadius.circular(Radii.large),
                border: picked ? Border.all(color: color, width: 2) : null,
              ),
              child: GlyphIcon(
                icon,
                size: 22,
                color: solid
                    ? Colors.white
                    : picked
                    ? color
                    : AppColors.muted,
              ),
            ),
            const SizedBox(height: Space.s1),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: TextSize.caption,
                fontWeight: lit ? FontWeight.w700 : FontWeight.w500,
                color: lit ? color : AppColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
