import 'package:flutter/material.dart';

import '../demo/ledger.dart';
import '../look/figures.dart';
import '../look/glyphs.dart';
import '../look/icons.dart';
import '../look/theme.dart';
import '../look/widgets.dart';

/// The icon of an entry: its category's, or transfer and trade marks.
(Glyph, Color) entryMark(Ledger ledger, Entry e) {
  final category = ledger.category(e.category);
  return switch (e.type) {
    EntryType.transfer => (iconFor('transfer'), Hue.transfer),
    EntryType.buy || EntryType.sell => (iconFor('investment'), Hue.investment),
    _ => (iconFor(category.icon), category.color),
  };
}

/// `−200`, `+52,000`, or a plain amount for transfers.
String entryAmount(Entry e) => switch (e.type) {
  EntryType.expense || EntryType.buy => spent(e.amount),
  EntryType.transfer => groupDigits(e.amount),
  _ => '+${groupDigits(e.amount)}',
};

/// 「飲食日常 · 隨身現金」, or the two accounts of a transfer.
String entryDetail(Ledger ledger, Entry e) {
  final account = ledger.account(e.account).name;
  final shares = '${e.holding} · ${e.shares} 股';
  return switch (e.type) {
    EntryType.transfer => '$account → ${ledger.account(e.to ?? '').name}',
    EntryType.buy || EntryType.sell => '$shares · $account',
    _ => '${e.category} · $account',
  };
}

/// One entry as a list row.
class EntryTile extends StatelessWidget {
  const EntryTile({
    super.key,
    required this.ledger,
    required this.entry,
    required this.onTap,
    this.repeat = false,
  });

  final Ledger ledger;
  final Entry entry;
  final VoidCallback onTap;

  /// The row above has the same mark: show a quiet dot instead of the
  /// badge again.
  final bool repeat;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = entryMark(ledger, entry);
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Hue.line)),
        ),
        child: Row(
          children: [
            if (repeat)
              SizedBox(
                width: 34,
                child: Center(
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.6),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              )
            else
              IconBadge(icon, color, size: 34),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    entryDetail(ledger, entry),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: Hue.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              ledger.hidden ? '••••' : entryAmount(entry),
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w500,
                color: entryColor(entry.type),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A date line over a group of entries.
class DayHeading extends StatelessWidget {
  const DayHeading(this.date, {super.key, this.total});

  final DateTime date;

  /// The day's spending, written on the right.
  final String? total;

  @override
  Widget build(BuildContext context) {
    final sum = total;
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 4),
      child: Row(
        children: [
          Text(
            longDay(date),
            style: const TextStyle(fontSize: 13, color: Hue.muted),
          ),
          const Spacer(),
          if (sum != null)
            Text(sum, style: const TextStyle(fontSize: 12, color: Hue.muted)),
        ],
      ),
    );
  }
}
