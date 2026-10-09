import 'package:flutter/material.dart';

import '../demo/ledger.dart';
import '../look/figures.dart';
import '../look/theme.dart';
import '../look/widgets.dart';
import 'dialogs.dart';
import 'nav.dart';

/// 定期交易: the next item, then items due, coming up, booked and
/// paused. Switches live under 「管理固定項目」.
class RecurringPage extends StatefulWidget {
  const RecurringPage({super.key, required this.ledger, required this.nav});

  final Ledger ledger;
  final Nav nav;

  @override
  State<RecurringPage> createState() => _RecurringPageState();
}

class _RecurringPageState extends State<RecurringPage> {
  var _manage = false;

  Future<void> _book(Recurring item) async {
    final ok = await confirm(
      context,
      '${item.name} ${groupDigits(item.amount)} 現在入帳？',
      '入帳',
    );
    if (ok) widget.ledger.confirm(item);
  }

  Future<void> _create() async {
    final ledger = widget.ledger;
    final name = await askText(context, '固定項目名稱');
    if (name == null || !mounted) return;
    final amount = await askAmount(context, '每期金額');
    if (amount == null || !mounted) return;
    final day = await askAmount(context, '每月幾號（1–28）');
    if (day == null) return;
    ledger.addRecurring(
      Recurring(
        id: ledger.newId(),
        name: name,
        amount: amount,
        day: day.clamp(1, 28),
        account: ledger.accounts.first.id,
        category: '其他支出',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ledger = widget.ledger;
    return ListenableBuilder(
      listenable: ledger,
      builder: (context, _) {
        final today = ledger.today;
        final due = ledger.due;
        final upcoming = ledger.upcoming;
        final booked = [
          for (final r in ledger.recurring)
            if (ledger.confirmation(r, today.year, today.month) case final e?)
              (r, e),
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
        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 0, 20, 32),
          children: [
            PageHeader('定期交易', onBack: widget.nav.back),
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SoftPanel(
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                due.isEmpty
                                    ? '尚無到期項目'
                                    : '${due.length} 筆已到期',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Hue.muted,
                                ),
                              ),
                              Text(
                                next?.name ?? '沒有固定項目',
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (next != null)
                                Text(
                                  '下一筆 ${today.month} / ${next.day} · '
                                  'TWD ${groupDigits(next.amount)}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Hue.muted,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: _create,
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('新增'),
                          style: FilledButton.styleFrom(
                            backgroundColor: Hue.white,
                            foregroundColor: Hue.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => setState(() => _manage = !_manage),
                      icon: const Icon(Icons.tune, size: 18),
                      label: Text(_manage ? '完成' : '管理固定項目'),
                      style: TextButton.styleFrom(foregroundColor: Hue.muted),
                    ),
                  ),
                  if (_manage)
                    for (final r in ledger.recurring)
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(r.name),
                        subtitle: Text(
                          '每月 ${r.day} 日 · ${groupDigits(r.amount)}',
                        ),
                        value: r.active,
                        onChanged: (_) => ledger.toggleRecurring(r.id),
                      )
                  else ...[
                    if (due.isNotEmpty) ...[
                      _Heading('已到期', due.length),
                      for (final r in due)
                        _Row(
                          ledger: ledger,
                          item: r,
                          status: '待確認',
                          onTap: () => _book(r),
                        ),
                    ],
                    _Heading('即將到期', upcoming.length),
                    for (final r in upcoming)
                      _Row(
                        ledger: ledger,
                        item: r,
                        status: '即將到期',
                        onTap: () => _book(r),
                      ),
                    _Heading('已入帳', booked.length),
                    for (final (r, e) in booked)
                      _Row(
                        ledger: ledger,
                        item: r,
                        status: '已入帳',
                        day: e.date.day,
                        amount: e.amount,
                        onTap: () => widget.nav.showEntry(e),
                      ),
                    if (paused.isNotEmpty) ...[
                      _Heading('已暫停', paused.length),
                      for (final r in paused)
                        _Row(
                          ledger: ledger,
                          item: r,
                          status: '已暫停',
                          onTap: () => setState(() => _manage = true),
                        ),
                    ],
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.title, this.count);

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    return SectionHead(
      title,
      trailing: Text(
        '$count 筆',
        style: const TextStyle(fontSize: 12, color: Hue.muted),
      ),
    );
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
  final int? day;
  final int? amount;

  @override
  Widget build(BuildContext context) {
    final muted = status == '已暫停';
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Hue.line)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              padding: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                color: Hue.surface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  Text(
                    '${ledger.today.month}月',
                    style: const TextStyle(fontSize: 10, color: Hue.muted),
                  ),
                  Text(
                    '${day ?? item.day}',
                    style: const TextStyle(fontSize: 18, color: Hue.muted),
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
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    ledger.account(item.account).name,
                    style: const TextStyle(fontSize: 12, color: Hue.muted),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  groupDigits(amount ?? item.amount),
                  style: TextStyle(
                    fontSize: 17,
                    color: muted ? Hue.muted : Hue.negative,
                  ),
                ),
                Text(
                  status,
                  style: const TextStyle(fontSize: 12, color: Hue.muted),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
