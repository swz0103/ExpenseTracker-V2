import 'package:flutter/material.dart';

import '../../../../design_system/display/amount.dart';
import '../../../../design_system/display/status.dart';
import '../../../core/design_system/glyphs.dart';
import '../../../core/design_system/theme.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/ledger/ledger.dart';
import '../../../core/widgets/problem_note.dart';
import '../../../core/navigation/nav.dart';
import '../../../core/widgets/shown_amounts.dart';
import '../../../core/design_system/shape.dart';
import '../../../core/design_system/spacing.dart';
import '../../../core/formatting/words.dart';
import '../../../core/messages/recurring_messages.dart' show pausedHint;
import 'recurring_rows.dart';
import 'recurring_page.dart';

// 管理固定項目, 訂閱與固定支出 and 已暫停.

/// A sub-page's frame: its header and what is under it.
class _SubPage extends StatelessWidget {
  const _SubPage({
    required this.title,
    required this.nav,
    required this.children,
    this.actions = const [],
  });

  final String title;
  final Nav nav;
  final List<Widget> children;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => HeadedList(
    padding: const EdgeInsets.fromLTRB(Space.s5, 0, Space.s5, Space.s8),
    header: CenterHeader(title, onBack: nav.back, actions: actions),
    children: [...children],
  );
}

/// 管理固定項目: every active item as a square, 支出 then 收入, each
/// side with how many and what they come to a month.
class RecurringManage extends StatelessWidget {
  const RecurringManage({
    super.key,
    required this.ledger,
    required this.nav,
    required this.onEdit,
  });

  final Ledger ledger;
  final Nav nav;
  final Future<void> Function({Recurring? item, DateTime? on}) onEdit;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      // The items, what they booked, their accounts and categories, and the
      // rates their yearly cost is valued at.
      listenable: ledger.watch(const {
        Topic.recurring,
        Topic.entries,
        Topic.accounts,
        Topic.categories,
        Topic.market,
      }),
      builder: (context, _) {
        final today = ledger.today;
        List<Widget> side(bool income) {
          final items = [
            for (final r in ledger.recurring.all)
              if (r.active && r.income == income) r,
          ];
          if (items.isEmpty) return const [];
          // What this month's dates come to: a yearly item counts only in
          // the month it falls, so the total is this month's (本月合計),
          // not a monthly average.
          var monthly = 0;
          for (final r in items) {
            monthly +=
                ledger.recurringService.worth(r) *
                r.datesIn(today.year, today.month).length;
          }
          return [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.s1,
                Space.s4,
                Space.s1,
                Space.s2,
              ),
              child: Row(
                children: [
                  Text(
                    income ? Words.income : Words.expense,
                    style: _sectionTitle,
                  ),
                  const SizedBox(width: Space.s2),
                  // Wraps under itself at large text rather than running
                  // past the edge.
                  Expanded(
                    child: Text(
                      '${items.length} 項 · 本月合計 ${ledger.orDots(groupDigits(monthly))}',
                      textAlign: TextAlign.end,
                      style: mutedSmall,
                    ),
                  ),
                ],
              ),
            ),
            for (final r in items) ...[
              RecurringRow(
                ledger: ledger,
                item: r,
                onTap: () => onEdit(item: r),
              ),
              const SizedBox(height: Space.s2),
            ],
          ];
        }

        return _SubPage(
          nav: nav,
          title: '管理固定項目',
          actions: [
            HeaderButton(glyph: Glyph.add, label: Words.add, onTap: onEdit),
          ],
          children: [...side(false), ...side(true)],
        );
      },
    );
  }
}

/// 訂閱與固定支出: what the fixed spending comes to a year and a month,
/// a bar of each item's share, and each item's year, month and share,
/// the dearest first.
class RecurringSubscriptions extends StatelessWidget {
  const RecurringSubscriptions({
    super.key,
    required this.ledger,
    required this.nav,
    required this.onEdit,
  });

  final Ledger ledger;
  final Nav nav;
  final Future<void> Function({Recurring? item, DateTime? on}) onEdit;

  @override
  Widget build(BuildContext context) {
    final rows = yearlyCostsOf(ledger);
    final total = rows.fold(0, (sum, row) => sum + row.$2);
    return _SubPage(
      nav: nav,
      title: '訂閱與固定支出',
      children: [
        if (rows.isEmpty)
          const EmptyState(
            glyph: Glyph.subscription,
            color: recurringColor,
            message: '還沒有固定支出',
          )
        else ...[
          ..._yearTotal(rows, total),
          const Padding(
            padding: EdgeInsets.fromLTRB(
              Space.s1,
              Space.s4,
              Space.s1,
              Space.s2,
            ),
            child: Row(
              children: [
                Expanded(child: Text('每一項一年多少', style: _sectionTitle)),
                SizedBox(width: Space.s2),
                Text('依金額', style: mutedSmall),
              ],
            ),
          ),
          for (final (item, yearly) in rows) ...[
            RecurringRow(
              ledger: ledger,
              item: item,
              onTap: () => onEdit(item: item),
              lines: [
                '一年 ${ledger.orDots(groupDigits(yearly))}',
                '每月 ${ledger.orDots(groupDigits(divideRounded(yearly, 12)))} · '
                    '佔 ${wholePercent(yearly, total)}',
              ],
            ),
            const SizedBox(height: Space.s2),
          ],
        ],
      ],
    );
  }

  /// 一年下來: what [rows] cost in a year together and a month on average,
  /// and each one's share of [total] as a bar in its colour.
  List<Widget> _yearTotal(List<(Recurring, int)> rows, int total) => [
    const Text(
      '一年下來',
      style: TextStyle(fontSize: TextSize.body, fontWeight: FontWeight.w700),
    ),
    Text(
      ledger.orDots(groupDigits(total)),
      style: const TextStyle(
        fontSize: TextSize.hero,
        fontWeight: FontWeight.w800,
      ),
    ),
    Text('平均每月 ${ledger.orDots(groupDigits(total ~/ 12))}', style: mutedSmall),
    const SizedBox(height: Space.s4),
    ClipRRect(
      borderRadius: BorderRadius.circular(Radii.small),
      child: SizedBox(
        height: 12,
        child: Row(
          children: [
            for (final (i, (item, yearly)) in rows.indexed) ...[
              if (i > 0) const SizedBox(width: Space.half),
              Expanded(
                flex: (yearly * 1000 ~/ total).clamp(1, 1000),
                child: ColoredBox(
                  color: recurringMark(ledger, item).$2,
                  child: const SizedBox.expand(),
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  ];
}

/// 已暫停: what pausing means, then each paused item in grey with 恢復.
class RecurringPaused extends StatelessWidget {
  const RecurringPaused({
    super.key,
    required this.ledger,
    required this.nav,
    required this.onEdit,
  });

  final Ledger ledger;
  final Nav nav;
  final Future<void> Function({Recurring? item, DateTime? on}) onEdit;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      // As the active items above.
      listenable: ledger.watch(const {
        Topic.recurring,
        Topic.entries,
        Topic.accounts,
        Topic.categories,
        Topic.market,
      }),
      builder: (context, _) {
        final paused = [
          for (final r in ledger.recurring.all)
            if (!r.active) r,
        ];
        return _SubPage(
          nav: nav,
          title: StatusWords.paused,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(Space.s1, 0, Space.s1, Space.s4),
              child: Text(pausedHint, style: mutedSmall),
            ),
            if (paused.isEmpty)
              const EmptyState(
                glyph: Glyph.cycleCalendar,
                color: recurringColor,
                message: '沒有暫停的項目',
              )
            else
              for (final r in paused) ...[
                RecurringRow(
                  ledger: ledger,
                  item: r,
                  grey: true,
                  onTap: () => onEdit(item: r),
                  trailing: FilledButton(
                    onPressed: () => refusalShown(
                      context,
                      () => ledger.recurringCommands.saveRecurring(
                        r.copyWith(active: true),
                      ),
                    ),
                    style: solidButton(
                      AppColors.white,
                      ink: AppColors.accent,
                      minimumSize: Size(0, 40),
                      radius: Radii.medium,
                      padding: const EdgeInsets.symmetric(horizontal: Space.s3),
                    ),
                    child: const Text(
                      Words.unarchive,
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                const SizedBox(height: Space.s2),
              ],
          ],
        );
      },
    );
  }
}

/// A heading over a group of items, such as 支出 or 每一項一年多少.
const _sectionTitle = TextStyle(
  fontSize: TextSize.title,
  fontWeight: FontWeight.w800,
);
