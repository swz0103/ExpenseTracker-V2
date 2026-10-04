import 'package:flutter/material.dart';

import '../book.dart';
import '../charts/chart_data.dart';
import '../theme.dart';

/// `$ 12,430`, or `- $ 8,420` below zero.
String dollars(int value) =>
    value < 0 ? '- \$ ${groupDigits(-value)}' : '\$ ${groupDigits(value)}';

/// An entry's amount as the list shows it: `-$180`, `+$36,000`, `$10,000`.
String entryAmount(Entry entry) => switch (entry.kind) {
  EntryKind.expense => '-\$${groupDigits(entry.amount)}',
  EntryKind.income => '+\$${groupDigits(entry.amount)}',
  EntryKind.transfer => '\$${groupDigits(entry.amount)}',
};

const _categoryIcons = {
  '餐飲': Icons.restaurant_outlined,
  '交通': Icons.directions_bus_outlined,
  '購物': Icons.shopping_bag_outlined,
  '居家': Icons.home_outlined,
  '娛樂': Icons.sports_esports_outlined,
  '醫療': Icons.medical_services_outlined,
  '教育': Icons.school_outlined,
  '薪資': Icons.payments_outlined,
  '投資': Icons.trending_up,
  '獎金': Icons.redeem_outlined,
  '轉帳': Icons.swap_horiz,
};

IconData categoryIcon(String category) =>
    _categoryIcons[category] ?? Icons.category_outlined;

const _accountIcons = {
  '現金': Icons.account_balance_wallet_outlined,
  '銀行': Icons.account_balance_outlined,
  '信用卡': Icons.credit_card_outlined,
  '電子票證': Icons.contactless_outlined,
  '證券': Icons.show_chart,
};

IconData accountIcon(String kind) =>
    _accountIcons[kind] ?? Icons.savings_outlined;

/// A line icon on a soft peach square, the app's basic mark.
class IconTile extends StatelessWidget {
  const IconTile(this.icon, {super.key, this.size = 40, this.selected = false});

  final IconData icon;
  final double size;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: selected ? Palette.clay : Palette.wash,
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(
        icon,
        size: size * 0.52,
        color: selected ? Palette.card : Palette.clay,
      ),
    );
  }
}

/// A white rounded panel.
class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color = Palette.card,
    this.onTap,
  });

  final Widget child;
  final EdgeInsets padding;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(16);
    return Material(
      color: color,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: color == Palette.card
            ? const BorderSide(color: Palette.line)
            : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// A row of pill-shaped choices, the selected one filled.
class PillTabs extends StatelessWidget {
  const PillTabs({
    super.key,
    required this.labels,
    required this.selected,
    required this.onChanged,
  });

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Palette.wash,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          for (final (i, label) in labels.indexed)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  decoration: BoxDecoration(
                    color: i == selected ? Palette.clay : Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    label,
                    style: text.labelLarge?.copyWith(
                      color: i == selected ? Palette.card : Palette.muted,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One entry as a list row: icon, title, where and how, amount.
class EntryRow extends StatelessWidget {
  const EntryRow(this.entry, {super.key, this.date});

  final Entry entry;

  /// Shown before the details when the list spans several days.
  final DateTime? date;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final detail = entry.kind == EntryKind.transfer
        ? '${entry.account} → ${entry.toAccount}'
        : [if (entry.place.isNotEmpty) entry.place, entry.account].join('・');
    final day = date;
    final when = day == null ? '' : '${day.month}/${day.day}・';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          IconTile(categoryIcon(entry.category), size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.title, style: text.bodyMedium),
                Text(
                  '$when$detail',
                  style: text.bodySmall?.copyWith(color: Palette.muted),
                ),
              ],
            ),
          ),
          Text(
            entryAmount(entry),
            style: text.bodyMedium?.copyWith(
              color: entry.kind == EntryKind.income
                  ? Palette.olive
                  : Palette.ink,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// A screen's title row: 「10 月 ˅」 and actions on the right.
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({
    super.key,
    required this.title,
    this.onTitleTap,
    this.actions = const [],
  });

  final String title;
  final VoidCallback? onTitleTap;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.headlineSmall
        ?.copyWith(fontWeight: FontWeight.w600);
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          InkWell(
            onTap: onTitleTap,
            borderRadius: BorderRadius.circular(8),
            child: Row(
              children: [
                Text(title, style: style),
                if (onTitleTap != null)
                  const Icon(Icons.keyboard_arrow_down, color: Palette.ink),
              ],
            ),
          ),
          const Spacer(),
          ...actions,
        ],
      ),
    );
  }
}

/// Says a screen or feature is still to come.
void comingSoon(BuildContext context, String what) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text('「$what」還在製作中')));
}
