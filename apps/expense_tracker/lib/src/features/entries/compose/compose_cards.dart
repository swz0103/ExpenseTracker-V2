import 'package:flutter/material.dart';

import '../../../core/text/figures.dart';
import '../../../core/look/glyphs.dart';
import '../../../core/ui/icons.dart';
import '../../../core/look/theme.dart';
import '../../../core/look/widgets.dart';
import '../../../core/ledger/ledger.dart';
import '../../../core/look/shape.dart';
import '../../../core/look/spacing.dart';

// The cards of the entry form's fields: a split's bar, a choice and the
// two ends of a transfer.

/// The parts of a split as one bar: each a stretch as wide as its share,
/// with its name and amount on it; a tap opens that part's amount.
class AllocationBar extends StatelessWidget {
  const AllocationBar({super.key, required this.parts, required this.onTap});

  final List<(Category, int)> parts;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: Space.s3),
      // 56 high, taller when the phone's text is larger.
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, (category, amount)) in parts.indexed) ...[
              if (i > 0) const SizedBox(width: Space.half),
              Expanded(
                flex: amount <= 0 ? 1 : amount,
                child: Material(
                  color: shownColor(Color(category.color)),
                  borderRadius: BorderRadius.circular(Radii.medium),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => onTap(i),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Space.s2,
                        vertical: Space.s2,
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 44),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              category.name,
                              maxLines: 1,
                              overflow: TextOverflow.clip,
                              softWrap: false,
                              style: TextStyle(
                                fontSize: TextSize.caption,
                                fontWeight: FontWeight.w700,
                                color: wordsOn(
                                  shownColor(Color(category.color)),
                                ),
                              ),
                            ),
                            Text(
                              groupDigits(amount),
                              maxLines: 1,
                              overflow: TextOverflow.clip,
                              softWrap: false,
                              style: TextStyle(
                                fontSize: TextSize.body,
                                fontWeight: FontWeight.w700,
                                color: wordsOn(
                                  shownColor(Color(category.color)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A white card with a mark and what was chosen, such as the account or
/// the day; [label] names it for a screen reader.
class PickCard extends StatelessWidget {
  const PickCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
    this.valueColor = Hue.ink,
  });

  final Glyph icon;
  final String label;
  final String value;
  final VoidCallback onTap;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(Radii.large);
    return Semantics(
      button: true,
      label: '$label：$value',
      excludeSemantics: true,
      child: Material(
        color: Hue.group,
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Space.s3,
                vertical: Space.s2,
              ),
              child: Row(
                children: [
                  SquareIcon(icon, Hue.accent, size: 30),
                  const SizedBox(width: Space.s2),
                  Expanded(
                    child: Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: TextSize.title,
                        fontWeight: FontWeight.w700,
                        color: valueColor,
                      ),
                    ),
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

/// One end of a transfer on a grey card: the account's mark on the left,
/// its name over what it will hold once the transfer is made. [end] is
/// the right-hand card, with room on its inner side for the arrow.
class TransferEndCard extends StatelessWidget {
  const TransferEndCard({
    super.key,
    required this.account,
    required this.after,
    required this.label,
    required this.onTap,
    this.end = false,
  });

  final Account account;

  /// What the account holds afterwards, as words.
  final String after;

  /// What a screen reader calls it: 轉出帳戶 or 轉入帳戶.
  final String label;
  final VoidCallback onTap;
  final bool end;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(Radii.large);
    return Semantics(
      button: true,
      label: '$label：${account.name}，$after',
      excludeSemantics: true,
      child: Material(
        color: Hue.surface,
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 60),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                end ? Space.s6 : Space.s3,
                Space.s2,
                end ? Space.s2 : Space.s6,
                Space.s2,
              ),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Hue.white,
                      borderRadius: BorderRadius.circular(Radii.medium),
                    ),
                    child: GlyphIcon(
                      accountIcon(account),
                      size: 17,
                      color: Hue.muted,
                    ),
                  ),
                  const SizedBox(width: Space.s2),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          account.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: TextSize.body,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          after,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: TextSize.caption,
                            color: Hue.muted,
                          ),
                        ),
                      ],
                    ),
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
