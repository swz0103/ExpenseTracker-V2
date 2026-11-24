import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/ledger/ledger.dart';
import '../../../core/design_system/glyphs.dart';
import '../../../core/design_system/shape.dart';
import '../../../core/design_system/spacing.dart';
import '../../../core/design_system/theme.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/widgets/icons.dart';
import '../../../core/widgets/shown_amounts.dart';
import '../../../core/widgets/entry_tile.dart' show entrySpoken;
import '../model/compose_form.dart';
import '../model/entry_details.dart';
import '../model/receipt_photos.dart';
import 'compose_cards.dart';
import 'receipt_square.dart';
import 'compose_mode_look.dart';
import '../../../core/formatting/words.dart';

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
      EntryType.transfer => (Glyph.transfer, AppColors.transfer),
      _ when trade => (Glyph.investment, AppColors.investment),
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
              semanticsLabel: entrySpoken(
                e,
                currency: currency,
                hidden: ledger.amounts.hidden,
              ),
              style: TextStyle(
                fontSize: TextSize.big,
                fontWeight: FontWeight.w800,
                height: 1.15,
                color: e.type == EntryType.transfer
                    ? AppColors.ink
                    : mode.color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// An entry looked at, [entry] as it stands: its marks ([marks], and 定期
/// for one booked by a recurring item), its [EntryViewCard], then a tile
/// for each thing written with it, two to a row, and its receipt photo.
/// Nothing that was left empty shows.
class EntryView extends StatelessWidget {
  const EntryView({
    super.key,
    required this.ledger,
    required this.entry,
    required this.mode,
    required this.marks,
    required this.photos,
    required this.receipt,
  });

  final Ledger ledger;
  final Entry entry;
  final ComposeMode mode;
  final List<(String, Color)> marks;
  final ReceiptPhotos? photos;
  final String? receipt;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final title = entryTitle(ledger.accounts, e);
    final photos = this.photos;
    final receipt = this.receipt;
    final cells = <Widget>[
      for (final (label, value) in entryDetails(
        ledger.accounts,
        e,
        title,
        today: ledger.today,
      ))
        ViewFieldTile(label: label, value: value),
      if (photos != null && receipt != null)
        TapArea(
          label: '查看收據',
          onTap: () => unawaited(showReceipt(context, photos.image(receipt))),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Radii.large),
            child: Image(
              image: photos.image(receipt),
              height: 64,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) =>
                  const ViewFieldTile(label: Words.receipt, value: '—'),
            ),
          ),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (marks.isNotEmpty || e.recurring != null)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.s2),
            child: Wrap(
              spacing: 6,
              children: [
                if (e.recurring != null) const Pill('定期'),
                for (final (label, c) in marks) Pill(label, color: c),
              ],
            ),
          ),
        EntryViewCard(ledger: ledger, entry: e, title: title, mode: mode),
        const SizedBox(height: Space.s2),
        CardGrid(gap: 8, cells),
      ],
    );
  }
}
