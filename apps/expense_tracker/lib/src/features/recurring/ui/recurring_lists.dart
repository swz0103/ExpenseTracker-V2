part of 'recurring_page.dart';

// 管理固定項目, 訂閱與固定支出 and 已暫停.

/// A sub-page's frame: its header and what is under it.
class _SubPage extends StatelessWidget {
  const _SubPage({
    required this.title,
    required this.children,
    this.actions = const [],
  });

  final String title;
  final List<Widget> children;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
    children: [
      CenterHeader(
        title,
        onBack: () => Navigator.of(context).pop(),
        actions: actions,
      ),
      ...children,
    ],
  );
}

/// 管理固定項目: every active item as a square, 支出 then 收入, each
/// side with how many and what they come to a month.
class _Manage extends StatelessWidget {
  const _Manage({required this.ledger, required this.onEdit});

  final Ledger ledger;
  final Future<void> Function({Recurring? item, DateTime? on}) onEdit;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ledger,
      builder: (context, _) {
        final today = ledger.today;
        List<Widget> side(bool income) {
          final items = [
            for (final r in ledger.recurring)
              if (r.active && r.income == income) r,
          ];
          if (items.isEmpty) return const [];
          var monthly = 0;
          for (final r in items) {
            monthly +=
                ledger.recurringWorth(r) *
                r.datesIn(today.year, today.month).length;
          }
          return [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 14, 4, 10),
              child: Row(
                children: [
                  Text(
                    income ? '收入' : '支出',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
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
              const SizedBox(height: 8),
            ],
          ];
        }

        return _SubPage(
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
  const _Subscriptions({required this.ledger});

  final Ledger ledger;

  @override
  Widget build(BuildContext context) {
    final rows = yearlyCosts(ledger);
    final total = rows.fold(0, (sum, row) => sum + row.$2);
    return _SubPage(
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
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          Text(
            ledger.orDots(groupDigits(total)),
            style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w800),
          ),
          Text(
            '平均每月 ${ledger.orDots(groupDigits(total ~/ 12))}',
            style: mutedSmall,
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 12,
              child: Row(
                children: [
                  for (final (i, (item, yearly)) in rows.indexed) ...[
                    if (i > 0) const SizedBox(width: 2),
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
            padding: EdgeInsets.fromLTRB(4, 18, 4, 10),
            child: Row(
              children: [
                Text(
                  '每一項一年多少',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
                Spacer(),
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
            const SizedBox(height: 8),
          ],
        ],
      ],
    );
  }
}

/// 已暫停: what pausing means, then each paused item in grey with 恢復.
class _Paused extends StatelessWidget {
  const _Paused({required this.ledger, required this.onEdit});

  final Ledger ledger;
  final Future<void> Function({Recurring? item, DateTime? on}) onEdit;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ledger,
      builder: (context, _) {
        final paused = [
          for (final r in ledger.recurring)
            if (!r.active) r,
        ];
        return _SubPage(
          title: '已暫停',
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 0, 4, 14),
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
                    onPressed: () =>
                        ledger.saveRecurring(r.copyWith(active: true)),
                    style: FilledButton.styleFrom(
                      backgroundColor: Hue.white,
                      foregroundColor: Hue.accent,
                      minimumSize: const Size(0, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      '恢復',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
          ],
        );
      },
    );
  }
}
