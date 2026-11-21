import 'package:flutter/material.dart';

import '../../../core/formatting/figures.dart';
import '../../../core/design_system/glyphs.dart';
import '../../../core/design_system/theme.dart';
import '../../../core/ledger/ledger.dart';
import '../../../core/widgets/shown_amounts.dart';
import '../../../core/design_system/shape.dart';
import '../../../core/design_system/spacing.dart';
import 'trade_cards.dart';
import '../../../core/formatting/words.dart';

// The page of every holding a trade may be in, opened from the entry
// form.

/// Every holding on a page of its own: a search, then cards three to a
/// row with their code, short name and shares, and 新增 at the end.
class HoldingChoices extends StatefulWidget {
  const HoldingChoices({
    super.key,
    required this.ledger,
    required this.selected,
    required this.onPick,
    this.onAdd,
  });

  final Ledger ledger;
  final String? selected;
  final ValueChanged<String> onPick;
  final VoidCallback? onAdd;

  @override
  State<HoldingChoices> createState() => _HoldingChoicesState();
}

class _HoldingChoicesState extends State<HoldingChoices> {
  var _typed = '';

  @override
  Widget build(BuildContext context) {
    final ledger = widget.ledger;
    final words = _typed.trim().toLowerCase();
    final cards = <Widget>[
      for (final h in ledger.holdings.all)
        if (words.isEmpty ||
            h.code.toLowerCase().contains(words) ||
            h.name.toLowerCase().contains(words))
          HoldingCard(
            code: h.code,
            name: shortHoldingName(h),
            held: h.shares > 0
                ? '${ledger.orDots(groupDigits(h.shares))} 股'
                : '已賣完',
            picked: h.code == widget.selected,
            onTap: () => widget.onPick(h.code),
          ),
    ];
    final add = widget.onAdd;
    if (add != null) {
      cards.add(_addCard(add));
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          onChanged: (text) => setState(() => _typed = text),
          decoration: InputDecoration(
            hintText: '搜尋代號或名稱',
            isDense: true,
            filled: true,
            fillColor: AppColors.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Radii.large),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: Space.s2),
        for (var i = 0; i < cards.length; i += 3)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.s2),
            // Every card in a row as tall as the tallest, 新增 included.
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var j = i; j < i + 3; j++) ...[
                    if (j > i) const SizedBox(width: Space.s2),
                    Expanded(
                      child: j < cards.length
                          ? cards[j]
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// 新增 as the last card, opening [add].
  static Widget _addCard(VoidCallback add) => Material(
    color: Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Radii.large),
      side: const BorderSide(color: AppColors.line, width: 1.5),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(Radii.large),
      onTap: add,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 74),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            GlyphIcon(Glyph.add, size: 20, color: AppColors.muted),
            Text(
              Words.add,
              style: TextStyle(
                fontSize: TextSize.small,
                fontWeight: FontWeight.w700,
                color: AppColors.muted,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
