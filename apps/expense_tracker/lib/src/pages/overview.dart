import 'dart:math';

import 'package:flutter/material.dart';

import '../charts/bar_scale.dart';
import '../charts/budget_bar.dart';
import '../charts/flow_chart.dart';
import '../demo/ledger.dart';
import '../look/figures.dart';
import '../look/glyphs.dart';
import '../look/icons.dart';
import '../look/theme.dart';
import '../look/widgets.dart';
import 'nav.dart';

/// 總覽: the month's balance, what falls due, a week of days with the
/// chosen day's entries, the market, spending against the budget, where
/// the assets are and six months of income and spending.
class OverviewPage extends StatefulWidget {
  const OverviewPage({super.key, required this.ledger, required this.nav});

  final Ledger ledger;
  final Nav nav;

  @override
  State<OverviewPage> createState() => _OverviewPageState();
}

class _OverviewPageState extends State<OverviewPage> {
  late var _month = (widget.ledger.today.year, widget.ledger.today.month);
  late DateTime _day = widget.ledger.today;
  var _dayPage = 0;
  var _scale = BarScale.enlarged;
  String? _holding;
  int? _piece;
  int? _tile;
  int? _flowMonth;

  static const _perPage = 6;

  DateTime get _monday => _day.subtract(Duration(days: _day.weekday - 1));

  void _moveWeek(int by) {
    final today = widget.ledger.today;
    var next = _day.add(Duration(days: 7 * by));
    if (next.isAfter(today)) next = today;
    setState(() {
      _day = next;
      _dayPage = 0;
      _month = (next.year, next.month);
    });
  }

  @override
  Widget build(BuildContext context) {
    final ledger = widget.ledger;
    return ListenableBuilder(
      listenable: ledger,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        children: [
          PageHeader(
            '總覽',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: ledger.hidden ? '顯示金額' : '隱藏金額',
                  onPressed: ledger.toggleHidden,
                  icon: GlyphIcon(
                    ledger.hidden ? Glyph.eyeOff : Glyph.eye,
                    size: 20,
                    color: Hue.muted,
                  ),
                ),
                MonthSwitch(
                  month: _month,
                  latest: (ledger.today.year, ledger.today.month),
                  onChanged: (month) => setState(() {
                    _month = month;
                    _flowMonth = null;
                    _piece = null;
                  }),
                ),
              ],
            ),
          ),
          _Summary(ledger: ledger, month: _month),
          const SizedBox(height: 16),
          const Divider(),
          _DueRow(
            ledger: ledger,
            onTap: () => widget.nav.open(Pages.recurring),
          ),
          const Divider(),
          ..._daily(),
          ..._market(),
          ..._budget(),
          ..._assets(),
          ..._flow(),
        ],
      ),
    );
  }

  List<Widget> _daily() {
    final ledger = widget.ledger;
    final monday = _monday;
    final sunday = monday.add(const Duration(days: 6));
    var weekSpent = 0;
    for (var d = 0; d < 7; d++) {
      weekSpent += ledger.spentOn(monday.add(Duration(days: d)));
    }
    final entries = ledger.entriesOn(_day);
    final pages = max(1, (entries.length / _perPage).ceil());
    final page = _dayPage.clamp(0, pages - 1);
    final shown = entries.skip(page * _perPage).take(_perPage).toList();
    final first = page * _perPage + 1;
    final last = min(entries.length, (page + 1) * _perPage);
    final atToday = !sunday.isBefore(ledger.today);
    final from = '${monday.month} / ${monday.day}';
    final to = '${sunday.month} / ${sunday.day}';
    return [
      SectionHead(
        '每日紀錄',
        trailing: Text(
          '本週 TWD ${groupDigits(weekSpent)}',
          style: const TextStyle(fontSize: 12, color: Hue.muted),
        ),
      ),
      Row(
        children: [
          IconButton(
            tooltip: '上一週',
            onPressed: () => _moveWeek(-1),
            icon: const GlyphIcon(Glyph.back, size: 18, color: Hue.muted),
          ),
          Expanded(
            child: Text(
              '$from 至 $to',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: Hue.muted),
            ),
          ),
          IconButton(
            tooltip: '下一週',
            onPressed: atToday ? null : () => _moveWeek(1),
            icon: const GlyphIcon(Glyph.next, size: 18),
          ),
        ],
      ),
      _WeekStrip(
        ledger: ledger,
        monday: monday,
        selected: _day,
        month: _month.$2,
        onSelect: (day) => setState(() {
          _day = day;
          _dayPage = 0;
        }),
      ),
      const SizedBox(height: 16),
      Row(
        children: [
          Flexible(
            child: Text(
              '${_day.month} 月 ${_day.day} 日',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 10),
          if (pages > 1)
            Flexible(
              child: InkWell(
                onTap: () => setState(() => _dayPage = (page + 1) % pages),
                child: Text(
                  '$first-$last / ${entries.length}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Hue.muted,
                    decoration: TextDecoration.underline,
                    decorationColor: Hue.muted,
                  ),
                ),
              ),
            ),
          const Spacer(),
          const Text('支出 ', style: TextStyle(fontSize: 13, color: Hue.muted)),
          Text(
            groupDigits(ledger.spentOn(_day)),
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: Hue.negative,
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      GestureDetector(
        onHorizontalDragEnd: (details) {
          final speed = details.primaryVelocity ?? 0.0;
          if (speed.abs() < 150 || pages < 2) return;
          setState(() {
            _dayPage = (page + (speed < 0 ? 1 : pages - 1)) % pages;
          });
        },
        child: _DayGrid(
          ledger: ledger,
          entries: shown,
          onTap: widget.nav.showEntry,
        ),
      ),
      const Divider(),
    ];
  }

  List<Widget> _market() {
    final ledger = widget.ledger;
    final change = ledger.dayChange;
    final before = ledger.investValue - change;
    final movers = [...ledger.holdings]
      ..sort((a, b) => b.change.abs().compareTo(a.change.abs()));
    final shown = movers.take(6).toList();
    final largest = shown.fold(0, (m, h) => max(m, h.change.abs()));
    final today = ledger.today;
    final code = _holding;
    final picked = code == null ? null : ledger.holding(code);
    final tone = change < 0 ? Hue.negative : Hue.positive;
    return [
      SectionHead(
        '投資行情',
        trailing: LinkToggle(
          _scale.label,
          onTap: () => setState(() => _scale = _scale.other),
        ),
      ),
      Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Figure(
              '${today.month}/${today.day} 當日損益',
              signed(change),
              color: tone,
              size: 22,
            ),
          ),
          Figure(
            '投資市值 · ${percentOf(change, before)}',
            groupDigits(ledger.investValue),
            end: true,
          ),
        ],
      ),
      const SizedBox(height: 10),
      for (final h in shown) _moverRow(h, largest),
      if (picked != null) _pickedHolding(picked),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          onPressed: () => widget.nav.open(Pages.investments),
          style: TextButton.styleFrom(foregroundColor: Hue.muted),
          child: Text('全部 ${ledger.holdings.length} 檔持股 ›'),
        ),
      ),
      const Divider(),
    ];
  }

  Widget _moverRow(Holding h, int largest) {
    final picked = h.code == _holding;
    return InkWell(
      onTap: () => setState(() => _holding = picked ? null : h.code),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
        decoration: BoxDecoration(
          color: picked ? Hue.selected.withValues(alpha: 0.6) : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 104,
              child: Text(
                h.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14),
              ),
            ),
            Expanded(
              child: AxisBar(
                value: h.change,
                largest: largest,
                scale: _scale,
                axis: 0.25,
                height: 8,
              ),
            ),
            SizedBox(
              width: 56,
              child: Text(
                signed(h.change),
                textAlign: TextAlign.end,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: h.change < 0 ? Hue.negative : Hue.positive,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pickedHolding(Holding h) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
      child: Text.rich(
        TextSpan(
          style: const TextStyle(fontSize: 13, color: Hue.muted),
          children: [
            TextSpan(
              text: '${h.code}　',
              style: const TextStyle(
                color: Hue.ink,
                fontWeight: FontWeight.w600,
              ),
            ),
            TextSpan(text: '市值 ${groupDigits(h.value)}　累計 '),
            TextSpan(
              text: '${signed(h.gain)}（${percentOf(h.gain, h.cost)}）',
              style: TextStyle(color: h.gain < 0 ? Hue.negative : Hue.positive),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _budget() {
    final ledger = widget.ledger;
    final (year, month) = _month;
    final rows = ledger.expenseByCategory(year, month);
    final spent = rows.fold(0, (sum, r) => sum + r.$2);
    final limit = ledger.budgetFor(Ledger.allSpending).limit;
    final piece = _piece == null || _piece! >= rows.length ? null : _piece;
    final label = piece == null ? '本月支出' : rows[piece].$1.name;
    final amount = piece == null ? spent : rows[piece].$2;
    return [
      SectionHead(
        '支出與預算',
        trailing: TextButton(
          onPressed: () => widget.nav.open(Pages.budgets),
          child: const Text('調整', style: TextStyle(color: Hue.positive)),
        ),
      ),
      Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Figure(
              label,
              'TWD ${groupDigits(amount)}',
              color: Hue.negative,
              size: 22,
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text(
                '剩餘預算',
                style: TextStyle(fontSize: 12, color: Hue.muted),
              ),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: 'TWD ${groupDigits(limit - spent)}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: limit < spent ? Hue.negative : Hue.ink,
                      ),
                    ),
                    TextSpan(
                      text: ' ／ ${groupDigits(limit)}',
                      style: const TextStyle(fontSize: 14, color: Hue.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      const SizedBox(height: 12),
      BudgetBar(
        pieces: [for (final (c, amount) in rows) (c.color, amount)],
        limit: limit,
        selected: piece,
        onSelect: (index) => setState(() => _piece = index),
      ),
      const SizedBox(height: 8),
      const Divider(),
    ];
  }

  List<Widget> _assets() {
    final ledger = widget.ledger;
    int sumOf(AccountKind kind) {
      var total = 0;
      for (final a in ledger.accounts) {
        if (a.kind == kind) total += ledger.balance(a.id);
      }
      return total;
    }

    final parts = [
      ('投資', ledger.investValue, Hue.holdings),
      ('銀行', sumOf(AccountKind.bank), Hue.bank),
      ('現金', sumOf(AccountKind.cash), Hue.cash),
      ('電子支付', sumOf(AccountKind.wallet), Hue.wallet),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    return [
      SectionHead(
        '資產分布',
        trailing: Text(
          'TWD ${groupDigits(ledger.assets)}',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      _Composition(
        parts: parts,
        selected: _tile,
        onSelect: (index) => setState(() => _tile = index),
      ),
      const SizedBox(height: 14),
      const Divider(),
    ];
  }

  List<Widget> _flow() {
    final ledger = widget.ledger;
    final (year, month) = _month;
    final today = ledger.today;
    final months = <FlowMonth>[];
    for (var back = 5; back >= 0; back--) {
      final first = DateTime.utc(year, month - back);
      final end = DateTime.utc(first.year, first.month + 1, 0);
      final until = end.isAfter(today) ? today : end;
      months.add(
        FlowMonth(
          '${first.month}月',
          ledger.income(first.year, first.month),
          ledger.expense(first.year, first.month),
          ledger.netWorthAt(until),
        ),
      );
    }
    final picked = (_flowMonth ?? months.length - 1).clamp(0, 5);
    final shown = months[picked];
    final shownMonth = DateTime.utc(year, month - 5 + picked);
    final current =
        shownMonth.year == today.year && shownMonth.month == today.month;
    final scope = current
        ? '${shownMonth.month}月 · ${today.day}日止'
        : '${shownMonth.month}月';
    final left = shown.income - shown.expense;
    return [
      const SectionHead(
        '收支對照',
        trailing: Text(
          '近六個月',
          style: TextStyle(fontSize: 12, color: Hue.muted),
        ),
      ),
      Row(
        children: [
          Text(scope, style: const TextStyle(fontSize: 13, color: Hue.muted)),
          const Spacer(),
          const Text('結餘 ', style: TextStyle(fontSize: 13, color: Hue.muted)),
          Text(
            'TWD ${groupDigits(left)}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: left < 0 ? Hue.negative : Hue.ink,
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: _Dotted(
              '收入',
              'TWD ${groupDigits(shown.income)}',
              Hue.positive,
              size: 20,
            ),
          ),
          Expanded(
            child: _Dotted(
              '支出',
              'TWD ${groupDigits(shown.expense)}',
              Hue.negative,
              size: 20,
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          Container(width: 16, height: 2, color: Hue.investment),
          const SizedBox(width: 6),
          const Text(
            '淨資產線',
            style: TextStyle(fontSize: 12, color: Hue.investment),
          ),
          const Spacer(),
          Text(
            'TWD ${groupDigits(shown.worth)}',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Hue.investment,
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      FlowChart(
        months: months,
        selected: picked,
        onSelect: (index) => setState(() => _flowMonth = index),
      ),
    ];
  }
}

/// 本月結餘 large, with 收入、支出 and 其中股息 under it.
class _Summary extends StatelessWidget {
  const _Summary({required this.ledger, required this.month});

  final Ledger ledger;
  final (int, int) month;

  @override
  Widget build(BuildContext context) {
    final (year, m) = month;
    final income = ledger.income(year, m);
    final expense = ledger.expense(year, m);
    final left = income - expense;
    final hidden = ledger.hidden;
    String show(int amount) => hidden ? '••••' : groupDigits(amount);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('本月結餘', style: TextStyle(fontSize: 13, color: Hue.muted)),
        const SizedBox(height: 2),
        Text(
          show(left),
          style: TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.w700,
            height: 1.2,
            color: left < 0 ? Hue.negative : Hue.ink,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _Dotted('收入', show(income), Hue.positive)),
            Expanded(child: _Dotted('支出', show(expense), Hue.negative)),
            Expanded(
              child: _Dotted(
                '其中股息',
                show(ledger.dividends(year, m)),
                Hue.investment,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _DueRow extends StatelessWidget {
  const _DueRow({required this.ledger, required this.onTap});

  final Ledger ledger;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final due = ledger.due;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: due.isEmpty ? Hue.gold : Hue.negative,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              due.isEmpty ? '尚無到期項目' : '${due.length} 筆已到期',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 8),
            Text(
              '即將到期 ${ledger.upcoming.length} 筆',
              style: const TextStyle(fontSize: 13, color: Hue.muted),
            ),
            const Spacer(),
            const GlyphIcon(Glyph.next, size: 18, color: Hue.muted),
          ],
        ),
      ),
    );
  }
}

class _WeekStrip extends StatelessWidget {
  const _WeekStrip({
    required this.ledger,
    required this.monday,
    required this.selected,
    required this.month,
    required this.onSelect,
  });

  final Ledger ledger;
  final DateTime monday;
  final DateTime selected;
  final int month;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color(0xFFF1EBDD),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          for (var d = 0; d < 7; d++)
            Expanded(child: _dayCell(monday.add(Duration(days: d)))),
        ],
      ),
    );
  }

  Widget _dayCell(DateTime day) {
    final picked = day == selected;
    final future = day.isAfter(ledger.today);
    final outside = day.month != month;
    final kinds = {for (final e in ledger.entriesOn(day)) e.type};
    final dots = [
      if (kinds.contains(EntryType.expense)) Hue.negative,
      if (kinds.contains(EntryType.income)) Hue.positive,
      if (kinds.contains(EntryType.transfer)) Hue.transfer,
      if (kinds.any((k) => k.index >= EntryType.buy.index)) Hue.investment,
    ];
    final ink = picked
        ? Hue.positive
        : future || outside
        ? Hue.faint
        : Hue.ink;
    return GestureDetector(
      onTap: future ? null : () => onSelect(day),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: picked ? Hue.selected : null,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(
              weekdayNames[day.weekday - 1],
              style: TextStyle(fontSize: 12, color: ink),
            ),
            const SizedBox(height: 4),
            Text(
              '${day.day}',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w500,
                color: ink,
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: 6,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final color in dots)
                    Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 1.5),
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A day's entries three to a row: icon and name above the amount.
class _DayGrid extends StatelessWidget {
  const _DayGrid({
    required this.ledger,
    required this.entries,
    required this.onTap,
  });

  final Ledger ledger;
  final List<Entry> entries;
  final ValueChanged<Entry> onTap;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Text('這天沒有紀錄', style: TextStyle(color: Hue.muted)),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth / 3;
        return Wrap(
          children: [
            for (final e in entries)
              SizedBox(
                width: width,
                child: InkWell(
                  onTap: () => onTap(e),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: _cell(e),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _cell(Entry e) {
    final category = ledger.category(e.category);
    final icon = switch (e.type) {
      EntryType.transfer => iconFor('transfer'),
      EntryType.buy || EntryType.sell => iconFor('investment'),
      _ => iconFor(category.icon),
    };
    final color = entryColor(e.type);
    final amount = switch (e.type) {
      EntryType.expense || EntryType.buy => spent(e.amount),
      EntryType.transfer => groupDigits(e.amount),
      _ => '+${groupDigits(e.amount)}',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            GlyphIcon(icon, size: 16, color: category.color),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                e.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14),
              ),
            ),
          ],
        ),
        Text(
          amount,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}

/// A coloured dot and label over an amount.
class _Dotted extends StatelessWidget {
  const _Dotted(this.label, this.value, this.color, {this.size = 18});

  final String label;
  final String value;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontSize: 12, color: Hue.muted)),
          ],
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: TextStyle(
              fontSize: size,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

/// Parts of a whole as one segmented bar with a row per part under it;
/// tapping a segment or a row picks that part.
class _Composition extends StatelessWidget {
  const _Composition({
    required this.parts,
    required this.selected,
    required this.onSelect,
  });

  final List<(String, int, Color)> parts;
  final int? selected;
  final ValueChanged<int?> onSelect;

  @override
  Widget build(BuildContext context) {
    final total = parts.fold<int>(0, (sum, p) => sum + max(0, p.$2));
    void pick(int i) => onSelect(selected == i ? null : i);
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 14,
            child: Row(
              children: [
                for (final (i, (_, amount, color)) in parts.indexed)
                  if (amount > 0)
                    Expanded(
                      flex: max(1, amount * 1000 ~/ max(1, total)),
                      child: GestureDetector(
                        onTap: () => pick(i),
                        child: Container(
                          margin: EdgeInsets.only(
                            right: i == parts.length - 1 ? 0 : 2,
                          ),
                          color: selected == null || selected == i
                              ? color
                              : color.withValues(alpha: 0.3),
                        ),
                      ),
                    ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        for (final (i, (name, amount, color)) in parts.indexed)
          InkWell(
            onTap: () => pick(i),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              decoration: BoxDecoration(
                color: selected == i
                    ? Hue.selected.withValues(alpha: 0.6)
                    : null,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(name, style: const TextStyle(fontSize: 14)),
                  const SizedBox(width: 8),
                  Text(
                    total == 0 ? '' : '${(amount * 100 / total).round()}%',
                    style: const TextStyle(fontSize: 12, color: Hue.muted),
                  ),
                  const Spacer(),
                  Text(
                    groupDigits(amount),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
