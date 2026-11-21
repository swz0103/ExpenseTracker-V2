import 'package:flutter/material.dart';

import '../../../core/ledger/ledger.dart';
import '../../../core/design_system/glyphs.dart';
import '../../../core/formatting/dates.dart';
import '../../../core/formatting/figures.dart';
import '../../../core/design_system/theme.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/design_system/shape.dart';
import '../../../core/design_system/spacing.dart';

// The chips and pills under the amount and among the fields of the
// entry form: 常用, someone's share, words to pick and their headings.

/// One of 常用 under the amount: a small white pill with a grey mark,
/// its name and amount, a tap from a filled form. [strong] writes the
/// name in ink, for a switch such as 代墊 at the front of the row.
class UsualChip extends StatelessWidget {
  const UsualChip({
    super.key,
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
        padding: const EdgeInsets.fromLTRB(
          Space.s1,
          Space.s1,
          Space.s3,
          Space.s1,
        ),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(Radii.full),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
              ),
              child: GlyphIcon(icon, size: 14, color: AppColors.muted),
            ),
            const SizedBox(width: Space.s2),
            Text(
              name,
              maxLines: 1,
              style: TextStyle(
                fontSize: TextSize.small,
                fontWeight: strong ? FontWeight.w700 : FontWeight.w400,
                color: strong ? AppColors.ink : AppColors.muted,
              ),
            ),
            if (figure != null) ...[
              const SizedBox(width: Space.s2),
              Text(
                figure,
                maxLines: 1,
                style: const TextStyle(
                  fontSize: TextSize.body,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
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
class LentShareChip extends StatelessWidget {
  const LentShareChip({
    super.key,
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
        padding: const EdgeInsets.fromLTRB(
          Space.s1,
          Space.s1,
          Space.s3,
          Space.s1,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(Radii.full),
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
                color: AppColors.white,
                shape: BoxShape.circle,
              ),
              child: GlyphIcon(Glyph.heart, size: 13, color: color),
            ),
            const SizedBox(width: Space.s2),
            Text(
              name,
              maxLines: 1,
              style: TextStyle(
                fontSize: TextSize.small,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            const SizedBox(width: Space.s2),
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
class UsualRow extends StatelessWidget {
  const UsualRow(this.children, {super.key, this.lead});

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
                margin: const EdgeInsets.symmetric(horizontal: Space.s2),
                color: AppColors.line,
              ),
          ],
          for (final (i, child) in children.indexed) ...[
            if (i > 0) const SizedBox(width: Space.s2),
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
class PersonPill extends StatelessWidget {
  const PersonPill({
    super.key,
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
        padding: EdgeInsets.only(
          left: Space.s1,
          right: clear == null ? Space.s3 : 0,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(Radii.full),
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
                        color: AppColors.white,
                        shape: BoxShape.circle,
                      ),
                      child: GlyphIcon(Glyph.heart, size: 13, color: color),
                    ),
                    const SizedBox(width: Space.s2),
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
                    const SizedBox(width: Space.s2),
                    Flexible(
                      child: Text(
                        sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: mutedCaption,
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
class OwedCard extends StatelessWidget {
  const OwedCard({
    super.key,
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
    final radius = BorderRadius.circular(Radii.large);
    return ReadAsButton(
      selected: picked,
      label: '$title，$when，$amount',
      onTap: onTap,
      child: Material(
        color: picked ? color.withValues(alpha: 0.12) : AppColors.surface,
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
              padding: const EdgeInsets.fromLTRB(
                Space.s3,
                Space.s2,
                Space.s2,
                Space.s2,
              ),
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
                        Text(when, maxLines: 1, style: mutedTiny),
                        const SizedBox(height: Space.half),
                        Text(
                          amount,
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: TextSize.title,
                            fontWeight: FontWeight.w700,
                            color: picked ? color : AppColors.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _TickMark(picked: picked, color: color),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The round mark in an [OwedCard]'s corner: white, or filled in
/// [color] with a ✓ when [picked].
class _TickMark extends StatelessWidget {
  const _TickMark({required this.picked, required this.color});

  final bool picked;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 20,
    height: 20,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: picked ? color : AppColors.white,
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
  );
}

/// A word to pick in a row of them, such as a merchant or a tag: grey,
/// or tinted and ringed in [color] when [picked].
class WordChip extends StatelessWidget {
  const WordChip(
    this.label,
    this.onTap, {
    super.key,
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
        padding: const EdgeInsets.symmetric(
          horizontal: Space.s3,
          vertical: Space.s2,
        ),
        decoration: BoxDecoration(
          color: picked ? color.withValues(alpha: 0.12) : AppColors.surface,
          borderRadius: BorderRadius.circular(Radii.medium),
          border: picked ? Border.all(color: color, width: 1.5) : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: TextSize.small,
            fontWeight: FontWeight.w700,
            color: picked ? color : AppColors.ink,
          ),
        ),
      ),
    );
  }
}

/// Words in a row that slides sideways, such as the merchants.
class WordRow extends StatelessWidget {
  const WordRow(this.children, {super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (i, child) in children.indexed) ...[
            if (i > 0) const SizedBox(width: Space.s2),
            child,
          ],
        ],
      ),
    );
  }
}

/// A small grey heading over a group of fields, such as 商家.
class GroupLabel extends StatelessWidget {
  const GroupLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Space.half,
        Space.s2,
        Space.half,
        Space.half,
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: TextSize.caption,
          fontWeight: FontWeight.w700,
          color: AppColors.muted,
        ),
      ),
    );
  }
}

/// The sums someone still owes as cards to tick in a row that slides
/// sideways: each what it was for ([titleOf]), when, and what is left of
/// it; those in [paying] ticked. Nothing when they owe nothing.
class OwedCardRow extends StatelessWidget {
  const OwedCardRow({
    super.key,
    required this.sums,
    required this.titleOf,
    required this.paying,
    required this.color,
    required this.onToggle,
  });

  final List<(Entry, int)> sums;
  final String Function(Entry sum) titleOf;
  final Set<String> paying;
  final Color color;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    if (sums.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: Space.s3),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final (i, (e, left)) in sums.indexed) ...[
              if (i > 0) const SizedBox(width: Space.s2),
              OwedCard(
                title: titleOf(e),
                when: e.group == null
                    ? formatMd(e.date)
                    : '${formatMd(e.date)} 一起付的',
                amount: groupDigits(left),
                picked: paying.contains(e.id),
                color: color,
                onTap: () => onToggle(e.id),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
