import 'package:flutter/material.dart';

import '../look/figures.dart';
import '../look/glyphs.dart';
import '../look/icons.dart';
import '../look/theme.dart';
import '../look/widgets.dart';
import '../model/ledger.dart';

/// The icon of an entry: its category's, or transfer and trade marks.
(Glyph, Color) entryMark(Ledger ledger, Entry e) {
  final category = ledger.category(e.category);
  return switch (e.type) {
    EntryType.transfer => (iconFor('transfer'), Hue.transfer),
    EntryType.buy || EntryType.sell => (iconFor('investment'), Hue.investment),
    _ => (iconFor(category.icon), category.color),
  };
}

/// [item]'s amount in its account's currency, as the screens write it.
String recurringAmount(Ledger ledger, Recurring item) =>
    amountIn(item.amount, ledger.account(item.account).currency);

/// `−200`, `+52,000`, or a plain amount for transfers, in the [currency]
/// of the entry's account.
String entryAmount(Entry e, {String currency = homeCode}) {
  final amount = amountIn(e.amount, currency);
  return switch (e.type) {
    EntryType.expense || EntryType.buy => '−$amount',
    EntryType.transfer => amount,
    _ => '+$amount',
  };
}

/// 「飲食日常 · 隨身現金」, or the two accounts of a transfer.
String entryDetail(Ledger ledger, Entry e) {
  final account = ledger.account(e.account).name;
  final shares = '${e.holding} · ${e.shares} 股';
  final category = e.parts.length > 1
      ? '${e.category} 等 ${e.parts.length} 類'
      : e.category;
  return switch (e.type) {
    EntryType.transfer => '$account → ${ledger.account(e.to ?? '').name}',
    EntryType.buy || EntryType.sell => '$shares · $account',
    EntryType.dividend when e.shares < 0 => '${e.holding} · 減資 ${-e.shares} 股',
    EntryType.dividend when e.shares > 0 =>
      '${e.holding} · ${e.split ? '分割' : '配股'} ${e.shares} 股',
    _ when e.isRefund => '退款 · $account',
    _ => [
      if (e.merchant.isNotEmpty) e.merchant,
      category,
      if (e.installments > 1) '${e.installments} 期',
      account,
    ].join(' · '),
  };
}

/// One entry as a list row.
class EntryTile extends StatelessWidget {
  const EntryTile({
    super.key,
    required this.ledger,
    required this.entry,
    required this.onTap,
    this.divider = true,
  });

  final Ledger ledger;
  final Entry entry;
  final VoidCallback onTap;

  /// A rule under the tile; the last one of a list goes without.
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = entryMark(ledger, entry);
    final currency = ledger.account(entry.account).currency;
    final shown = ledger.hidden
        ? '••••'
        : entryAmount(entry, currency: currency);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            border: divider
                ? const Border(bottom: BorderSide(color: Hue.line))
                : null,
          ),
          child: Row(
            children: [
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
                      style: const TextStyle(fontSize: 13, color: Hue.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                shown,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w500,
                  color: entryColor(entry.type),
                ),
              ),
            ],
          ),
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
            Text(sum, style: const TextStyle(fontSize: 13, color: Hue.muted)),
        ],
      ),
    );
  }
}
