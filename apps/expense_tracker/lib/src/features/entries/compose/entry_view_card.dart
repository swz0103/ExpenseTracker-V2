import 'package:flutter/material.dart';

import '../../../core/ledger/ledger.dart';
import '../../../core/look/glyphs.dart';
import '../../../core/look/shape.dart';
import '../../../core/look/spacing.dart';
import '../../../core/look/theme.dart';
import '../../../core/look/widgets.dart';
import '../../../core/ui/icons.dart';
import '../../../core/ui/shown_amounts.dart';
import '../model/compose_form.dart';
import '../model/entry_details.dart';
import 'compose_mode_look.dart';

/// The card on top of an entry looked at: in its colour with its mark,
/// what kind it is ([mode]), what it is called ([title]), and its amount.
class EntryViewCard extends StatelessWidget {
  const EntryViewCard({
    super.key,
    required this.ledger,
    required this.entry,
    required this.title,
    required this.mode,
  });

  final Ledger ledger;
  final Entry entry;
  final String title;
  final ComposeMode mode;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final category = ledger.category(e.category);
    final trade = e.type.index >= EntryType.buy.index;
    final (Glyph glyph, Color color) = switch (e.type) {
      EntryType.transfer => (Glyph.transfer, Hue.transfer),
      _ when trade => (Glyph.investment, Hue.investment),
      _ => (iconFor(category.icon), shownColor(Color(category.color))),
    };
    final kind = switch (e.type) {
      EntryType.transfer => mode.label,
      _ when trade => mode.label,
      _ => '${mode.label} · ${category.name}',
    };
    final currency = ledger.account(e.account).currency;
    return ColorCard(
      color: color,
      radius: Radii.largeIncreased,
      padding: const EdgeInsets.fromLTRB(
        Space.s4,
        Space.s4,
        Space.s4,
        Space.s4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SquareIcon(glyph, color, size: 52),
              const SizedBox(width: Space.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    OneLine(kind, style: mutedSmall),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: TextSize.title,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.s2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              '${entrySign(e.type)}${ledger.moneyIn(e.amount, currency)}',
              style: TextStyle(
                fontSize: TextSize.big,
                fontWeight: FontWeight.w800,
                height: 1.15,
                color: e.type == EntryType.transfer ? Hue.ink : mode.color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
