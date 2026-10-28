import 'package:flutter/material.dart';

import '../../accounts/compose/account_editor.dart';
import '../compose/recurring_editor.dart';
import '../../../core/look/figures.dart';
import '../../../core/look/glyphs.dart';
import '../../../core/look/icons.dart';
import '../../../core/look/theme.dart';
import '../../../core/look/widgets.dart';
import '../../../core/ledger/ledger.dart';
import '../../../core/ui/entry_tile.dart';
import '../../../core/nav.dart';
import '../model/subscriptions.dart';

/// 定期交易: the next item, then items due, coming up, booked and
/// paused. Booking opens the composer so the amount can change; every
/// item opens its own form under 「管理固定項目」.
class RecurringPage extends StatefulWidget {
  const RecurringPage({super.key, required this.ledger, required this.nav});

  final Ledger ledger;
  final Nav nav;

  @override
  State<RecurringPage> createState() => _RecurringPageState();
}

class _RecurringPageState extends State<RecurringPage> {
  var _manage = false;

  void _book(Recurring item) {
    widget.nav.compose(draft: widget.ledger.booking(item));
  }

  Future<void> _edit([Recurring? item]) async {
    if (!await ensureAccount(context, widget.ledger) || !mounted) return;
    await editRecurring(context, widget.ledger, item: item);
  }

  @override
  Widget build(BuildContext context) {
    final ledger = widget.ledger;
    return ListenableBuilder(
      listenable: ledger.watch(const {
        Area.entries,
        Area.recurring,
        Area.accounts,
        Area.categories,
      }),
      builder: (context, _) {
        final today = ledger.today;
        final due = ledger.due;
        final upcoming = ledger.upcoming;
        final booked = [
          for (final r in ledger.recurring)
            for (final e in ledger.confirmationsIn(r, today.year, today.month))
              (r, e),
        ];
        final active = [
          for (final r in ledger.recurring)
            if (r.active) r,
        ];
        final paused = [
          for (final r in ledger.recurring)
            if (!r.active) r,
        ];
        final next = due.isNotEmpty
            ? due.first
            : upcoming.isNotEmpty
            ? upcoming.first
            : null;
        final nextDay = next == null ? null : ledger.nextDate(next);
        var monthly = 0;
        for (final r in active) {
          if (r.income) continue;
          final times = r.datesIn(today.year, today.month).length;
          monthly += ledger.recurringWorth(r) * times;
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          children: [
            PageHeader('定期交易', onBack: widget.nav.back),
            Tile(
              hero: true,
              icon: Glyph.subscription,
              label: next == null
                  ? '下一筆'
                  : due.isEmpty
                  ? '下一筆 · ${nextDay?.month}/${nextDay?.day}'
                  : '${due.length} 筆已到期',
              value: next?.name ?? '沒有固定項目',
              size: 28,
              sub: next?.rhythm,
              trailing: next == null
                  ? null
                  : Text(
                      ledger.orDots(recurringAmount(ledger, next)),
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: next.income ? Hue.positive : Hue.negative,
                      ),
                    ),
              onTap: next == null ? null : () => _book(next),
            ),
            TileRow([
              Tile(
                icon: Glyph.recurring,
                label: '本月固定支出',
                value: ledger.money(monthly),
                sub: '共 ${active.length} 項',
              ),
              Tile(
                icon: Glyph.add,
                label: '新增固定項目',
                value: '＋ 新增',
                size: 16,
                onTap: _edit,
              ),
            ]),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => setState(() => _manage = !_manage),
                icon: const GlyphIcon(Glyph.sliders, size: 18),
                label: Text(_manage ? '完成' : '管理固定項目'),
                style: TextButton.styleFrom(foregroundColor: Hue.muted),
              ),
            ),
            if (_manage)
              _Card([
                for (final r in ledger.recurring)
                  _Row(
                    ledger: ledger,
                    item: r,
                    day: ledger.nextDate(r),
                    status: r.rhythm,
                    onTap: () => _edit(r),
                  ),
              ])
            else ...[
              if (due.isNotEmpty) ...[
                _Heading('已到期', due.length),
                _Card([
                  for (final r in due)
                    _Row(
                      ledger: ledger,
                      item: r,
                      day: ledger.pendingDate(r),
                      status: '入帳',
                      onTap: () => _book(r),
                    ),
                ]),
              ],
              _Heading('即將到期', upcoming.length),
              _Card([
                for (final r in upcoming)
                  _Row(
                    ledger: ledger,
                    item: r,
                    day: ledger.pendingDate(r),
                    status: r.rhythm,
                    onTap: () => _book(r),
                  ),
              ]),
              _Heading('已入帳', booked.length),
              _Card([
                for (final (r, e) in booked)
                  _Row(
                    ledger: ledger,
                    item: r,
                    day: e.date,
                    amount: e.amount,
                    status: '已入帳',
                    onTap: () => widget.nav.showEntry(e),
                  ),
              ]),
              if (paused.isNotEmpty) ...[
                _Heading('已暫停', paused.length),
                _Card([
                  for (final r in paused)
                    _Row(
                      ledger: ledger,
                      item: r,
                      status: '已暫停',
                      onTap: () => _edit(r),
                    ),
                ]),
              ],
              ..._subscriptions(ledger),
            ],
          ],
        );
      },
    );
  }
}

/// 訂閱總覽: what the fixed spending costs a year, item by item.
List<Widget> _subscriptions(Ledger ledger) {
  final rows = yearlyCosts(ledger);
  if (rows.isEmpty) return const [];
  final total = rows.fold(0, (sum, row) => sum + row.$2);
  return [
    SectionHead(
      '訂閱總覽',
      trailing: Text('一年約 ${ledger.money(total)}', style: mutedSmall),
    ),
    SoftPanel(
      color: Hue.white,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Column(
        children: [
          for (final (i, (item, yearly)) in rows.indexed)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: i == 0 ? null : ruleAbove,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.name, style: const TextStyle(fontSize: 14)),
                        Text(item.rhythm, style: mutedSmall),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '每年 ${ledger.money(yearly)}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        '每月約 ${ledger.money(yearly ~/ 12)}',
                        style: mutedSmall,
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
    Padding(
      padding: const EdgeInsets.only(top: 6, left: 4),
      child: Text('依接下來 12 個月的扣款次數計，共 ${rows.length} 項', style: mutedSmall),
    ),
  ];
}

class _Card extends StatelessWidget {
  const _Card(this.rows);

  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    return SoftPanel(
      color: Hue.white,
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(children: rows),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.title, this.count);

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    return SectionHead(title, trailing: Text('$count 筆', style: mutedSmall));
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.ledger,
    required this.item,
    required this.status,
    required this.onTap,
    this.day,
    this.amount,
  });

  final Ledger ledger;
  final Recurring item;
  final String status;
  final VoidCallback onTap;
  final DateTime? day;
  final int? amount;

  @override
  Widget build(BuildContext context) {
    final muted = !item.active;
    final date = day;
    final category = ledger.category(item.category);
    final account = ledger.account(item.account);
    final currency = account.currency;
    final booked = amount;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: ruleBelow,
          child: Row(
            children: [
              Container(
                width: 42,
                padding: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  color: Hue.tile,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: date == null
                    ? IconBadge(
                        iconFor(category.icon),
                        category.color,
                        size: 30,
                      )
                    : Column(
                        children: [
                          Text(
                            '${date.month}月',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Hue.muted,
                            ),
                          ),
                          Text(
                            '${date.day}',
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: muted ? Hue.muted : Hue.ink,
                      ),
                    ),
                    Text(
                      '${item.category} · ${account.name}',
                      style: mutedSmall,
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    booked == null
                        ? ledger.orDots(recurringAmount(ledger, item))
                        : ledger.moneyIn(booked, currency),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: muted
                          ? Hue.muted
                          : item.income
                          ? Hue.positive
                          : Hue.negative,
                    ),
                  ),
                  Text(status, style: mutedSmall),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
