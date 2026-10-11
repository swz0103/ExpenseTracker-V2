import 'dart:math';

import 'package:flutter/material.dart';

import '../charts/bar_scale.dart';
import '../charts/flow_chart.dart';
import '../charts/treemap.dart';
import '../demo/ledger.dart';
import '../look/figures.dart';
import '../look/glyphs.dart';
import '../look/icons.dart';
import '../look/theme.dart';
import '../look/widgets.dart';
import 'nav.dart';

/// 總覽: the month in four figures, what falls due, a week of days with
/// the chosen day's entries, the market, spending against the budget,
/// where the assets are and six months of income and spending.
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
  static const _scale = BarScale.proportional;
  String? _holding;
  int? _tile;

  /// The opened part of 財務分布: null for all assets, else 'investment'
  /// or an account kind's name.
  String? _assetGroup;
  int? _flowMonth;

  static const _perPage = 6;

  /// [text], or dots while amounts are hidden.
  String _m(String text) => widget.ledger.hidden ? '••••' : text;

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
                  }),
                ),
              ],
            ),
          ),
          _Summary(ledger: ledger, month: _month),
          TileRow([_budgetTile(), _dueTile()]),
          ..._daily(),
          ..._market(),
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
    final last = min(entries.length, (page + 1) * _perPage);
    final atToday = !sunday.isBefore(ledger.today);
    final from = '${monday.month} / ${monday.day}';
    final to = '${sunday.month} / ${sunday.day}';
    return [
      SectionHead(
        '每日紀錄',
        trailing: Text(
          '本週 ${_m(groupDigits(weekSpent))}',
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
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: _WeekStrip(
          key: ValueKey(monday),
          ledger: ledger,
          monday: monday,
          selected: _day,
          month: _month.$2,
          onSelect: (day) => setState(() {
            _day = day;
            _dayPage = 0;
          }),
        ),
      ),
      const Padding(
        padding: EdgeInsets.only(top: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _Legend('支出', Hue.negative),
            _Legend('收入', Hue.positive),
            _Legend('轉帳', Hue.transfer),
            _Legend('投資', Hue.investment),
          ],
        ),
      ),
      const SizedBox(height: 14),
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
          const SizedBox(width: 8),
          Text(
            '${entries.length} 筆',
            style: const TextStyle(fontSize: 12, color: Hue.muted),
          ),
          const Spacer(),
          const Text('支出 ', style: TextStyle(fontSize: 13, color: Hue.muted)),
          Text(
            _m(groupDigits(ledger.spentOn(_day))),
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
          onAdd: () => widget.nav.compose(),
        ),
      ),
      if (pages > 1)
        Center(
          child: TextButton(
            onPressed: () => setState(() => _dayPage = (page + 1) % pages),
            style: TextButton.styleFrom(
              foregroundColor: Hue.accent,
              minimumSize: const Size(44, 44),
            ),
            child: Text(
              last < entries.length
                  ? '還有 ${entries.length - last} 筆 ›'
                  : '‹ 回到前 $_perPage 筆',
            ),
          ),
        ),
    ];
  }

  List<Widget> _market() {
    final ledger = widget.ledger;
    final holdings = ledger.holdings;
    final change = ledger.dayChange;
    final before = ledger.investValue - change;
    final largest = holdings.fold(0, (m, h) => max(m, h.change.abs()));
    final anyLoss = holdings.any((h) => h.change < 0);
    final today = ledger.today;
    final code = _holding;
    final picked = code == null ? null : ledger.holding(code);
    final tone = change < 0 ? Hue.negative : Hue.positive;
    return [
      SectionHead(
        '投資行情',
        trailing: Text(
          '${today.month}/${today.day} 收盤 · 示意',
          style: const TextStyle(fontSize: 12, color: Hue.muted),
        ),
      ),
      TileRow([
        Tile(
          icon: Glyph.investment,
          label: '今日損益',
          value: _m(signed(change)),
          valueColor: tone,
          sub: '當日 ${percentOf(change, before)}',
        ),
        Tile(
          icon: Glyph.briefcase,
          label: '持股市值',
          value: _m(groupDigits(ledger.investValue)),
          sub: '${holdings.length} 檔',
          onTap: () => widget.nav.open(Pages.investments),
        ),
      ]),
      const SizedBox(height: 8),
      for (final h in holdings) _moveRow(h, largest, anyLoss ? 0.3 : 0),
      if (picked != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text.rich(
            TextSpan(
              style: const TextStyle(fontSize: 12, color: Hue.muted),
              children: [
                TextSpan(
                  text: '${picked.name} ${picked.code}　',
                  style: const TextStyle(
                    color: Hue.ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                TextSpan(text: '市值 ${_m(groupDigits(picked.value))}　累計 '),
                TextSpan(
                  text: _m(
                    '${signed(picked.gain)}'
                    '（${percentOf(picked.gain, picked.cost)}）',
                  ),
                  style: TextStyle(
                    color: picked.gain < 0 ? Hue.negative : Hue.positive,
                  ),
                ),
              ],
            ),
          ),
        ),
    ];
  }

  /// One holding as a row of a bar chart: its name, today's move as a bar
  /// from a shared axis, and the amount.
  Widget _moveRow(Holding h, int largest, double axis) {
    final picked = h.code == _holding;
    return InkWell(
      onTap: () => setState(() => _holding = picked ? null : h.code),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
        decoration: BoxDecoration(
          color: picked ? Hue.selected.withValues(alpha: 0.6) : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 112,
              child: Text(
                h.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13),
              ),
            ),
            Expanded(
              child: AxisBar(
                value: h.change,
                largest: largest,
                scale: _scale,
                axis: axis,
                height: 8,
                minimum: 0.08,
              ),
            ),
            SizedBox(
              width: 50,
              child: Text(
                _m(signed(h.change)),
                textAlign: TextAlign.end,
                style: TextStyle(
                  fontSize: 13,
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

  /// 預算: what is left of the month's limit, with the share spent as a
  /// ring and the share of the month gone by.
  Widget _budgetTile() {
    final ledger = widget.ledger;
    final (year, month) = _month;
    final spent = ledger.expense(year, month);
    final limit = ledger.budgetFor(Ledger.allSpending).limit;
    final pace = (_pace(year, month) * 100).round();
    return Tile(
      icon: Glyph.budget,
      label: '預算',
      trailing: const Text(
        '調整',
        style: TextStyle(fontSize: 12, color: Hue.accent),
      ),
      lead: RingGauge(share: limit == 0 ? 0 : spent / limit, size: 50),
      value: _m(groupDigits(limit - spent)),
      valueColor: limit < spent ? Hue.negative : Hue.ink,
      size: 18,
      sub: '剩餘 · 時間 $pace%',
      onTap: () => widget.nav.open(Pages.budgets),
    );
  }

  /// 即將扣款: how many recurring items are due or coming, and the next
  /// two.
  Widget _dueTile() {
    final ledger = widget.ledger;
    final today = ledger.today;
    final due = ledger.due;
    final items = [...due, ...ledger.upcoming];
    return Tile(
      icon: Glyph.calendar,
      label: due.isEmpty ? '即將扣款' : '已到期',
      trailing: const GlyphIcon(Glyph.next, size: 16, color: Hue.muted),
      value: '${items.length} 筆',
      valueColor: due.isEmpty ? Hue.ink : Hue.negative,
      sub: items.isEmpty
          ? '沒有待扣款項目'
          : [
              for (final r in items.take(2))
                '${today.month}/${r.day} ${r.name} '
                    '${_m(groupDigits(r.amount))}',
            ].join('\n'),
      onTap: () => widget.nav.open(Pages.recurring),
    );
  }

  /// How much of the month has gone by: today's share of its days for
  /// the current month, all of it for past ones.
  double _pace(int year, int month) {
    final today = widget.ledger.today;
    if (year != today.year || month != today.month) return 1;
    final days = DateTime.utc(year, month + 1, 0).day;
    return today.day / days;
  }

  /// Colours for the second level of 財務分布, in v114's order.
  static const _shades = Hue.shades;

  /// The tiles of 財務分布 at the current level, largest first, each with
  /// the key it opens to.
  List<(String, String, int, Color)> _assetParts() {
    final ledger = widget.ledger;
    final group = _assetGroup;
    List<(String, String, int, Color)> shaded(List<(String, String, int)> l) {
      l.sort((a, b) => b.$3.compareTo(a.$3));
      return [
        for (final (i, (key, name, value)) in l.indexed)
          (key, name, value, _shades[i % _shades.length]),
      ];
    }

    if (group == 'investment') {
      return shaded([
        for (final h in ledger.holdings)
          if (h.value > 0) (h.code, h.code, h.value),
      ]);
    }
    if (group != null) {
      return shaded([
        for (final a in ledger.accounts)
          if (a.kind.name == group && ledger.balance(a.id) > 0)
            (a.id, a.name, ledger.balance(a.id)),
      ]);
    }
    int sumOf(AccountKind kind) {
      var total = 0;
      for (final a in ledger.accounts) {
        if (a.kind == kind) total += max(0, ledger.balance(a.id));
      }
      return total;
    }

    final parts = [
      ('investment', '投資', ledger.investValue, Hue.holdings),
      ('bank', '銀行', sumOf(AccountKind.bank), Hue.bank),
      ('cash', '現金', sumOf(AccountKind.cash), Hue.cash),
      ('wallet', '電子支付', sumOf(AccountKind.wallet), Hue.wallet),
    ]..sort((a, b) => b.$3.compareTo(a.$3));
    return [
      for (final p in parts)
        if (p.$3 > 0) p,
    ];
  }

  void _openAssets(String? group) {
    setState(() {
      _assetGroup = group;
      _tile = null;
    });
  }

  List<Widget> _assets() {
    final parts = _assetParts();
    final group = _assetGroup;
    final tile = _tile == null || _tile! >= parts.length ? null : _tile;
    final total = parts.fold<int>(0, (sum, p) => sum + p.$3);
    final scope = switch (group) {
      null => '資產',
      'investment' => '資產 › 投資',
      _ => '資產 › ${_groupLabel(group)}',
    };
    final allName = switch (group) {
      null => '全部資產',
      'investment' => '全部持股',
      _ => '全部帳戶',
    };
    final shownName = tile == null ? allName : parts[tile].$2;
    final shownAmount = tile == null ? total : parts[tile].$3;
    final share = tile == null || total == 0
        ? ''
        : '　${(shownAmount * 100 / total).round()}%';
    return [
      SectionHead(
        '財務分布',
        trailing: Text(
          _m(groupDigits(shownAmount)),
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      Row(
        children: [
          Text(scope, style: const TextStyle(fontSize: 12, color: Hue.muted)),
          const SizedBox(width: 6),
          Text(
            '$shownName$share',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          if (tile != null)
            _SmallLink('全部', () => setState(() => _tile = null)),
          if (group != null) _SmallLink('返回資產', () => _openAssets(null)),
        ],
      ),
      const SizedBox(height: 8),
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 280),
        switchInCurve: Curves.easeOutCubic,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1).animate(animation),
            child: child,
          ),
        ),
        child: Treemap(
          key: ValueKey(group),
          tiles: [for (final p in parts) (p.$2, p.$3, p.$4)],
          selected: tile,
          onSelect: (index) => setState(() => _tile = index),
          onOpen: (index) =>
              _openAssets(group == null ? parts[index].$1 : null),
        ),
      ),
    ];
  }

  String _groupLabel(String group) => switch (group) {
    'bank' => '銀行',
    'cash' => '現金',
    'wallet' => '電子支付',
    _ => group,
  };

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
          Text(
            scope,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          const Spacer(),
          Text(
            '結餘 ${_m(groupDigits(left))}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: left < 0 ? Hue.negative : Hue.ink,
            ),
          ),
        ],
      ),
      const SizedBox(height: 4),
      Row(
        children: [
          const _Key(Hue.positive, '收入'),
          Text(
            ' ${_m(groupDigits(shown.income))}',
            style: const TextStyle(fontSize: 12, color: Hue.muted),
          ),
          const SizedBox(width: 12),
          const _Key(Hue.negative, '支出'),
          Text(
            ' ${_m(groupDigits(shown.expense))}',
            style: const TextStyle(fontSize: 12, color: Hue.muted),
          ),
          const Spacer(),
          const _Key(Hue.investment, '淨資產', line: true),
          Text(
            ' ${_m(groupDigits(shown.worth))}',
            style: const TextStyle(fontSize: 12, color: Hue.muted),
          ),
        ],
      ),
      const SizedBox(height: 10),
      FlowChart(
        months: months,
        selected: picked,
        onSelect: (index) => setState(() => _flowMonth = index),
      ),
    ];
  }
}

/// The month's balance as the page's main tile, with income, spending
/// and dividends along its foot.
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
    final rate = income == 0 ? 0 : (left * 100 / income).round();
    String shown(int value) => ledger.hidden ? '••••' : groupDigits(value);
    return Tile(
      hero: true,
      icon: Glyph.wallet,
      label: '本月結餘',
      value: shown(left),
      valueColor: left < 0 ? Hue.negative : Hue.ink,
      trailing: Pill('結餘率 $rate%'),
      child: TileStats([
        (Glyph.income, '收入', shown(income), Hue.positive),
        (Glyph.payout, '支出', shown(expense), Hue.negative),
        (
          Glyph.dividend,
          '股息',
          shown(ledger.dividends(year, m)),
          Hue.investment,
        ),
      ]),
    );
  }
}

class _WeekStrip extends StatelessWidget {
  const _WeekStrip({
    super.key,
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
        color: Hue.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: Hue.cardShadow,
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
        ? Hue.accent
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

class _Legend extends StatelessWidget {
  const _Legend(this.label, this.color);

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 12, color: Hue.muted)),
        ],
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
    required this.onAdd,
  });

  final Ledger ledger;
  final List<Entry> entries;
  final ValueChanged<Entry> onTap;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          children: [
            const Text('這天沒有紀錄', style: TextStyle(color: Hue.muted)),
            const Spacer(),
            TextButton(
              onPressed: onAdd,
              style: TextButton.styleFrom(foregroundColor: Hue.accent),
              child: const Text('＋ 記一筆'),
            ),
          ],
        ),
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
    final amount = ledger.hidden
        ? '••••'
        : switch (e.type) {
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
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
        Text(
          amount,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}

/// A legend mark, a square or a short line, with its label.
class _Key extends StatelessWidget {
  const _Key(this.color, this.label, {this.line = false});

  final Color color;
  final String label;
  final bool line;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: line ? 12 : 8,
          height: line ? 2 : 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12, color: Hue.muted)),
      ],
    );
  }
}

class _SmallLink extends StatelessWidget {
  const _SmallLink(this.label, this.onTap);

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: Text(
          label,
          style: const TextStyle(fontSize: 12, color: Hue.accent),
        ),
      ),
    );
  }
}
