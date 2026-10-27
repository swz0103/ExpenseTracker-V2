import 'package:flutter/material.dart';

import '../look/figures.dart';
import '../look/glyphs.dart';
import '../look/haptics.dart';
import '../look/icons.dart';
import '../look/theme.dart';
import '../look/widgets.dart';
import '../ledger/ledger.dart';
import 'swipe_actions.dart';

/// The icon of an entry: its category's, or transfer and trade marks.
(Glyph, Color) entryMark(Ledger ledger, Entry e) {
  final category = ledger.category(e.category);
  return switch (e.type) {
    EntryType.transfer => (iconFor('transfer'), Hue.transfer),
    EntryType.buy || EntryType.sell => (iconFor('investment'), Hue.investment),
    _ => (iconFor(category.icon), category.color),
  };
}

/// The letter a row shows for [e] in place of its category's icon: the
/// first of its merchant's name, so a day of meals does not read as one
/// row of the same icon. Null when there is no merchant, or for transfers
/// and trades.
String? entryLetter(Entry e) {
  if (e.merchant.trim().isEmpty) return null;
  return switch (e.type) {
    EntryType.expense || EntryType.income => e.merchant.trim().characters.first,
    _ => null,
  };
}

/// The mark of [e] as a round badge: its merchant's first letter, or its
/// icon, in its category's colour.
Widget entryBadge(Ledger ledger, Entry e, {double size = 34}) {
  final (icon, color) = entryMark(ledger, e);
  return switch (entryLetter(e)) {
    final letter? => IconBadge.letter(letter, color, size: size),
    null => IconBadge(icon, color, size: size),
  };
}

/// 「2330 台積電」, or only the code while the name is not known (the
/// name then falls back to the code).
String holdingLabel(Holding h) =>
    h.name == h.code || h.name.isEmpty ? h.code : '${h.code} ${h.name}';

/// The colour of [e]'s amount: refunds in a quiet colour, as they give
/// spending back rather than bring income.
Color entryTone(Entry e) => e.isRefund ? Hue.muted : entryColor(e.type);

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
    _ when e.isRefund => switch (ledger.byId(e.refundOf!)) {
      final original? => '↩ 退款 · 原：${original.title}',
      null => '↩ 退款 · $account',
    },
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
    final currency = ledger.account(entry.account).currency;
    // A spending partly given back shows what is left of it.
    final back = entry.type == EntryType.expense ? ledger.refunded(entry) : 0;
    final shown = ledger.orDots(
      back == 0
          ? entryAmount(entry, currency: currency)
          : '−${amountIn(entry.amount - back, currency)}',
    );
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: divider ? ruleBelow : null,
          child: Row(
            children: [
              entryBadge(ledger, entry),
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
                      style: mutedSmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    shown,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w500,
                      color: entryTone(entry),
                    ),
                  ),
                  if (back > 0)
                    Text(
                      ledger.orDots('已退 ${amountIn(back, currency)}'),
                      style: mutedSmall,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// An entry as a list row that slides open to 編輯 and 刪除; a delete can
/// be undone from the note it leaves. While [onPick] is set, a long press
/// picks the entry instead.
class EntryRow extends StatelessWidget {
  const EntryRow({
    super.key,
    required this.ledger,
    required this.entry,
    required this.onOpen,
    this.divider = true,
    this.onLongPress,
  });

  final Ledger ledger;
  final Entry entry;

  /// Shows the entry to edit it, from a tap or 編輯.
  final ValueChanged<Entry> onOpen;
  final bool divider;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return SwipeActions(
      key: ValueKey(entry.id),
      actions: [
        SwipeAction('編輯', Hue.accent, () => onOpen(entry)),
        SwipeAction('刪除', Hue.danger, () => removeEntry(context, ledger, entry)),
      ],
      child: GestureDetector(
        onLongPress: onLongPress,
        child: EntryTile(
          ledger: ledger,
          entry: entry,
          divider: divider,
          onTap: () => onOpen(entry),
        ),
      ),
    );
  }
}

/// Deletes [entry], leaving a note to undo it; false when the book
/// refuses (it would oversell shares), which it says itself.
bool removeEntry(BuildContext context, Ledger ledger, Entry entry) {
  Haptics.medium();
  final removed = ledger.remove(entry.id);
  if (removed == null) return false;
  showNote(
    context,
    '已刪除「${entry.title}」',
    action: '復原',
    onAction: () => ledger.restore(removed),
  );
  return true;
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
          Text(longDay(date), style: mutedSmall),
          const Spacer(),
          if (sum != null) Text(sum, style: mutedSmall),
        ],
      ),
    );
  }
}
