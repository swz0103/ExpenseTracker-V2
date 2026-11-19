part of 'recurring_page.dart';

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
class _Manage extends StatelessWidget {
  const _Manage({
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
      listenable: ledger,
      builder: (context, _) {
        final today = ledger.today;
        List<Widget> side(bool income) {
          final items = [
            for (final r in ledger.recurring.all)
              if (r.active && r.income == income) r,
          ];
          if (items.isEmpty) return const [];
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
                  Text(income ? '收入' : '支出', style: _sectionTitle),
                  const Spacer(),
                  Text(
                    '${items.length} 項 · 每月 ${ledger.orDots(groupDigits(monthly))}',
                    style: mutedSmall,
                  ),
                ],
              ),
            ),
            for (final r in items) ...[
              _ItemRow(
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
          actions: [HeaderButton(glyph: Glyph.add, label: '新增', onTap: onEdit)],
          children: [...side(false), ...side(true)],
        );
      },
    );
  }
}

/// 訂閱與固定支出: what the fixed spending comes to a year and a month,
/// a bar of each item's share, and each item's year, month and share,
/// the dearest first.
class _Subscriptions extends StatelessWidget {
  const _Subscriptions({required this.ledger, required this.nav});

  final Ledger ledger;
  final Nav nav;

  @override
  Widget build(BuildContext context) {
    final rows = yearlyCosts(ledger);
    final total = rows.fold(0, (sum, row) => sum + row.$2);
    return _SubPage(
      nav: nav,
      title: '訂閱與固定支出',
      children: [
        if (rows.isEmpty)
          const EmptyState(
            glyph: Glyph.subscription,
            color: _recurringHue,
            message: '還沒有固定支出',
          )
        else ...[
          const Text(
            '一年下來',
            style: TextStyle(
              fontSize: TextSize.body,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            ledger.orDots(groupDigits(total)),
            style: const TextStyle(
              fontSize: TextSize.hero,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            '平均每月 ${ledger.orDots(groupDigits(total ~/ 12))}',
            style: mutedSmall,
          ),
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
                        color: _mark(ledger, item).$2,
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
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
            _ItemRow(
              ledger: ledger,
              item: item,
              onTap: () {},
              lines: [
                '一年 ${ledger.orDots(groupDigits(yearly))}',
                '每月 ${ledger.orDots(groupDigits(yearly ~/ 12))} · '
                    '佔 ${yearly * 100 ~/ total}%',
              ],
            ),
            const SizedBox(height: Space.s2),
          ],
        ],
      ],
    );
  }
}

/// 已暫停: what pausing means, then each paused item in grey with 恢復.
class _Paused extends StatelessWidget {
  const _Paused({
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
      listenable: ledger,
      builder: (context, _) {
        final paused = [
          for (final r in ledger.recurring.all)
            if (!r.active) r,
        ];
        return _SubPage(
          nav: nav,
          title: '已暫停',
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(Space.s1, 0, Space.s1, Space.s4),
              child: Text('暫停的項目不會出現在月曆上，也不算進每月固定支出。', style: mutedSmall),
            ),
            if (paused.isEmpty)
              const EmptyState(
                glyph: Glyph.cycleCalendar,
                color: _recurringHue,
                message: '沒有暫停的項目',
              )
            else
              for (final r in paused) ...[
                _ItemRow(
                  ledger: ledger,
                  item: r,
                  grey: true,
                  onTap: () => onEdit(item: r),
                  trailing: FilledButton(
                    onPressed: () => ledger.recurringCommands.saveRecurring(
                      r.copyWith(active: true),
                    ),
                    style: solidButton(
                      Hue.white,
                      ink: Hue.accent,
                      minimumSize: Size(0, 40),
                      radius: Radii.medium,
                      padding: const EdgeInsets.symmetric(horizontal: Space.s3),
                    ),
                    child: const Text(
                      '恢復',
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
