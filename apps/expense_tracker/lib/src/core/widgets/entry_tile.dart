import 'package:flutter/material.dart';

import '../../../design_system/display/amount.dart';
import '../design_system/glyphs.dart';
import '../design_system/haptics.dart';
import 'icons.dart';
import '../design_system/theme.dart';
import '../design_system/design_system.dart';
import '../ledger/ledger.dart';
import 'swipe_actions.dart';
import 'shown_amounts.dart';
import '../../../design_system/display/date.dart';
import '../design_system/spacing.dart';
import '../formatting/words.dart';
import '../../../design_system/display/amount_text.dart';

/// The icon of an entry: its category's, or transfer and trade marks.
(Glyph, Color) entryMark(Ledger ledger, Entry e) {
  final category = ledger.category(e.category);
  return switch (e.type) {
    EntryType.transfer => (iconFor('transfer'), AppColors.transfer),
    EntryType.buy ||
    EntryType.sell => (iconFor('investment'), AppColors.investment),
    _ => (iconFor(category.icon), shownColor(Color(category.color))),
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
    final letter? => RoundIcon.letter(letter, color, size: size),
    null => RoundIcon(icon, color, size: size),
  };
}

/// 「2330 台積電」, or only the code while the name is not known (the
/// name then falls back to the code).
String holdingLabel(Holding h) =>
    h.name == h.code || h.name.isEmpty ? h.code : '${h.code} ${h.name}';

/// The colour of [e]'s amount: refunds in a quiet colour, as they give
/// spending back rather than bring income.
Color entryTone(Entry e) => e.isRefund ? AppColors.muted : entryColor(e.type);

/// [item]'s amount in its account's currency, as the screens write it.
String recurringAmount(Ledger ledger, Recurring item) =>
    amountIn(item.amount, ledger.account(item.account).currency);

/// How [e]'s amount reads: spending (−) for spending and buys, nothing
/// for a transfer, income (+) for the rest.
AmountSense entrySense(Entry e) => switch (e.type) {
  EntryType.expense || EntryType.buy => AmountSense.spending,
  EntryType.transfer => AmountSense.plain,
  _ => AmountSense.income,
};

/// What a screen reader says for [entryAmount]: 支出 200 元, 收入 52,000
/// 元; 金額已隱藏 while [hidden].
String entrySpoken(
  Entry e, {
  String currency = homeCode,
  bool hidden = false,
}) => spokenAmount(
  e.amount,
  currency: currency,
  sense: entrySense(e),
  hidden: hidden,
);

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
  final shares = '${e.holding} · ${countOf(e.shares, CountUnit.shares)}';
  final category = e.parts.length > 1
      ? '${e.category} 等 ${e.parts.length} 類'
      : e.category;
  return switch (e.type) {
    EntryType.transfer => '$account → ${ledger.account(e.to ?? '').name}',
    EntryType.buy || EntryType.sell => '$shares · $account',
    EntryType.dividend when e.shares < 0 =>
      '${e.holding} · 減資 ${countOf(-e.shares, CountUnit.shares)}',
    EntryType.dividend when e.shares > 0 =>
      '${e.holding} · ${e.split ? '分割' : '配股'} ${countOf(e.shares, CountUnit.shares)}',
    _ when e.isRefund => switch (ledger.entries.byId(e.refundOf!)) {
      final original? => '↩ 退款 · 原：${original.title}',
      null => '↩ 退款 · $account',
    },
    _ => [
      if (e.merchant.isNotEmpty) e.merchant,
      category,
      if (e.installments > 1) countOf(e.installments, CountUnit.periods),
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
    this.merge = false,
  });

  final Ledger ledger;
  final Entry entry;
  final VoidCallback onTap;

  /// Shows an entry written as one with what was paid in it for others
  /// as the whole: in the record list, which leaves the others out.
  final bool merge;

  /// A rule under the tile; the last one of a list goes without.
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final currency = ledger.account(entry.account).currency;
    // A spending partly given back shows what is left of it.
    final back = entry.type == EntryType.expense
        ? ledger.entryQueryService.refunded(entry)
        : 0;
    // Written as one with what was paid for others: the whole paid, and
    // for whom how much.
    final group = merge ? ledger.entryQueryService.groupOf(entry) : [entry];
    final lent = [
      for (final m in group)
        if (m.type == EntryType.transfer) m,
    ];
    final whole = group.fold(0, (sum, m) => sum + m.amount);
    final shown = ledger.orDots(
      group.length > 1
          ? '−${amountIn(whole - back, currency)}'
          : back == 0
          ? entryAmount(entry, currency: currency)
          : '−${amountIn(entry.amount - back, currency)}',
    );
    final spoken = group.length > 1
        ? ledger.spoken(
            whole - back,
            currency: currency,
            sense: AmountSense.spending,
          )
        : back == 0
        ? ledger.spoken(
            entry.amount,
            currency: currency,
            sense: entrySense(entry),
          )
        : ledger.spoken(
            entry.amount - back,
            currency: currency,
            sense: AmountSense.spending,
          );
    final forOthers = group.length < 2
        ? null
        : '代墊 ${[for (final m in lent) '${ledger.account(m.to ?? m.account).name} ${ledger.orDots(groupDigits(m.amount))}'].join('、')}';
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.s4),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: Space.s2),
          decoration: divider ? ruleBelow : null,
          child: Row(
            children: [
              entryBadge(ledger, entry),
              const SizedBox(width: Space.s3),
              Expanded(child: _words(forOthers)),
              const SizedBox(width: Space.s2),
              _amount(shown, spoken, back, currency),
            ],
          ),
        ),
      ),
    );
  }

  /// The entry's title over what it is and which account, and for whom
  /// how much when part was paid for others ([forOthers]).
  Widget _words(String? forOthers) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        entry.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: TextSize.body,
          fontWeight: FontWeight.w500,
        ),
      ),
      Text(
        entryDetail(ledger, entry),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: mutedSmall,
      ),
      if (forOthers != null)
        Text(
          forOthers,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: TextSize.caption,
            fontWeight: FontWeight.w600,
            color: AppColors.receivable,
          ),
        ),
    ],
  );

  /// The amount [shown] in the entry's colour, read out as [spoken], and
  /// under it how much was given [back] in [currency], if any.
  Widget _amount(String shown, String spoken, int back, String currency) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          AmountText(
            shown,
            spoken: spoken,
            style: TextStyle(
              fontSize: TextSize.title,
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
      );
}

/// An entry as a list row that slides open to 編輯 and 刪除; a delete can
/// be undone from the note it leaves. While `onPick` is set, a long press
/// picks the entry instead.
class EntryRow extends StatelessWidget {
  const EntryRow({
    super.key,
    required this.ledger,
    required this.entry,
    required this.onOpen,
    this.divider = true,
    this.onLongPress,
    this.merge = false,
  });

  final Ledger ledger;
  final Entry entry;

  /// Shows the entry to edit it, from a tap or 編輯.
  final ValueChanged<Entry> onOpen;
  final bool divider;
  final VoidCallback? onLongPress;

  /// As [EntryTile.merge].
  final bool merge;

  @override
  Widget build(BuildContext context) {
    return SwipeActions(
      key: ValueKey(entry.id),
      actions: [
        SwipeAction(Words.edit, AppColors.accent, () => onOpen(entry)),
        SwipeAction(
          Words.delete,
          AppColors.danger,
          () => removeEntry(context, ledger, entry),
        ),
      ],
      child: GestureDetector(
        onLongPress: onLongPress,
        child: EntryTile(
          ledger: ledger,
          entry: entry,
          divider: divider,
          merge: merge,
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
  // An entry written as one with others goes with them.
  final removed = ledger.entryCommands.removeAll([
    for (final e in ledger.entryQueryService.groupOf(entry)) e.id,
  ]);
  if (removed.isEmpty) return false;
  showNote(
    context,
    '已刪除「${entry.title}」',
    action: '復原',
    onAction: () => ledger.entryCommands.restoreAll(removed),
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
      padding: const EdgeInsets.only(top: Space.s4, bottom: Space.s1),
      // At the two ends, or the total under the day when both do not
      // fit, as with the phone's largest text.
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        runSpacing: Space.half,
        children: [
          Text(formatMMMEd(date), style: mutedSmall),
          if (sum != null) Text(sum, style: mutedSmall),
        ],
      ),
    );
  }
}
