import 'dart:math';

import 'package:flutter/material.dart';

import '../charts/bar_scale.dart';
import '../charts/flow_chart.dart';
import '../charts/treemap.dart';
import '../look/figures.dart';
import '../look/glyphs.dart';
import '../look/icons.dart';
import '../look/theme.dart';
import '../look/widgets.dart';
import '../model/ledger.dart';
import 'entry_tile.dart';
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
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
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
          '本週 ${money(weekSpent)}',
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
      // A swipe across the week goes to the week before or after.
      GestureDetector(
        onHorizontalDragEnd: (details) {
          final speed = details.primaryVelocity ?? 0.0;
          if (speed.abs() < 150) return;
          if (speed < 0 && atToday) return;
          _moveWeek(speed < 0 ? 1 : -1);
        },
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          // Only the new week shows: two faded strips read as a smear.
          layoutBuilder: (current, previous) => current ?? const SizedBox(),
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
      ),
      const Padding(
        padding: EdgeInsets.only(top: 6),
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 10,
          children: [
            LegendKey(Hue.negative, '支出'),
            LegendKey(Hue.positive, '收入'),
            LegendKey(Hue.transfer, '轉帳'),
            LegendKey(Hue.investment, '投資'),
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
            money(ledger.spentOn(_day)),
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
    // Nothing to show before the first trade.
    if (holdings.isEmpty) return const [];
    final change = ledger.dayChange;
    final before = ledger.investValue - change;
    final largest = holdings.fold(0, (m, h) => max(m, h.change.abs()));
    final anyLoss = holdings.any((h) => h.change < 0);
    final code = _holding;
    final picked = code == null ? null : ledger.holding(code);
    final tone = change < 0 ? Hue.negative : Hue.positive;
    return [
      SectionHead(
        '投資行情',
        trailing: Text(switch (ledger.quotedOn) {
          final d? => '${d.month}/${d.day} 收盤',
          null => '尚未取得收盤價',
        }, style: const TextStyle(fontSize: 12, color: Hue.muted)),
      ),
      TileRow([
        Tile(
          icon: Glyph.investment,
          label: '當日損益',
          value: _m(signed(change)),
          valueColor: tone,
          sub: '當日 ${percentOf(change, before)}',
        ),
        Tile(
          icon: Glyph.briefcase,
          label: '持股市值',
          value: money(ledger.investValue),
          sub: '${holdings.length} 檔',
          onTap: () => widget.nav.open(Pages.investments),
        ),
      ]),
      const SizedBox(height: 8),
      for (final h in holdings) _moveRow(h, largest, anyLoss ? 0.5 : 0),
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
                TextSpan(text: '市值 ${money(picked.value)}　累計 '),
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
    final limit = ledger.allowance(
      ledger.budgetFor(Ledger.allSpending),
      year,
      month,
    );
    final pace = (_pace(year, month) * 100).round();
    return Tile(
      icon: Glyph.budget,
      label: '預算',
      trailing: const Text(
        '調整',
        style: TextStyle(fontSize: 12, color: Hue.accent),
      ),
      lead: RingGauge(share: limit == 0 ? 0 : spent / limit, size: 50),
      value: money(limit - spent),
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
                [
                  ledger.nextLabel(r),
                  r.name,
                  _m(recurringAmount(ledger, r)),
                ].join(' '),
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
          if (a.kind.name == group && _counted(a) && ledger.worthOf(a) > 0)
            (a.id, a.name, ledger.worthOf(a)),
      ]);
    }
    int sumOf(AccountKind kind) {
      var total = 0;
      for (final a in ledger.accounts) {
        if (a.kind == kind && _counted(a)) {
          total += max(0, ledger.worthOf(a));
        }
      }
      return total;
    }

    final parts = [
      ('investment', '投資', ledger.investValue, Hue.holdings),
      for (final kind in const [
        AccountKind.bank,
        AccountKind.cash,
        AccountKind.wallet,
        AccountKind.receivable,
      ])
        (kind.name, groupName(kind), sumOf(kind), accountColor(kind)),
    ]..sort((a, b) => b.$3.compareTo(a.$3));
    return [
      for (final p in parts)
        if (p.$3 > 0) p,
    ];
  }

  /// Whether [a] counts toward 財務分布: in net worth and still open.
  static bool _counted(Account a) => a.inNetWorth && !a.archived;

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
    if (total == 0 && group == null) return const [];
    final scope = switch (group) {
      null => '資產',
      'investment' => '資產 › 投資',
      _ => '資產 › ${groupName(AccountKind.values.byName(group))}',
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
          money(shownAmount),
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      // One height whether or not the links show, so a tap on the map
      // does not push the page down.
      SizedBox(
        height: 36,
        child: Row(
          children: [
            Text(scope, style: const TextStyle(fontSize: 12, color: Hue.muted)),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                '$shownName$share',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Spacer(),
            if (tile != null)
              _SmallLink('全部', () => setState(() => _tile = null)),
            if (group != null) _SmallLink('返回資產', () => _openAssets(null)),
          ],
        ),
      ),
      const SizedBox(height: 4),
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
            '結餘 ${money(left)}',
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
          const LegendKey(Hue.positive, '收入'),
          Text(
            ' ${money(shown.income)}',
            style: const TextStyle(fontSize: 12, color: Hue.muted),
          ),
          const SizedBox(width: 12),
          const LegendKey(Hue.negative, '支出'),
          Text(
            ' ${money(shown.expense)}',
            style: const TextStyle(fontSize: 12, color: Hue.muted),
          ),
          const Spacer(),
          const LegendKey(Hue.investment, '淨資產', line: true),
          Text(
            ' ${money(shown.worth)}',
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
    return Tile(
      hero: true,
      icon: Glyph.wallet,
      label: '本月結餘',
      value: money(left),
      valueColor: left < 0 ? Hue.negative : Hue.ink,
      trailing: Pill('結餘率 $rate%'),
      child: TileStats([
        (Glyph.income, '收入', money(income), Hue.positive),
        (Glyph.payout, '支出', money(expense), Hue.negative),
        (
          Glyph.dividend,
          '其中股息',
          money(ledger.dividends(year, m)),
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
    // Three to a row on a white card, each set apart by thin rules.
    const across = 3;
    final rows = <Widget>[];
    for (var i = 0; i < entries.length; i += across) {
      if (i > 0) rows.add(const Divider(height: 1, indent: 12, endIndent: 12));
      rows.add(
        IntrinsicHeight(
          child: Row(
            children: [
              for (var k = i; k < i + across; k++) ...[
                if (k > i)
                  VerticalDivider(
                    width: 1,
                    indent: 10,
                    endIndent: 10,
                    color: k < entries.length ? Hue.line : Colors.transparent,
                  ),
                Expanded(
                  child: k < entries.length
                      ? InkWell(
                          onTap: () => onTap(entries[k]),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                            child: _cell(entries[k]),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        ),
      );
    }
    return SoftPanel(
      color: Hue.white,
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(children: rows),
    );
  }

  Widget _cell(Entry e) {
    final (icon, mark) = entryMark(ledger, e);
    final color = entryColor(e.type);
    final currency = ledger.account(e.account).currency;
    final amount = ledger.hidden ? '••••' : entryAmount(e, currency: currency);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            GlyphIcon(icon, size: 16, color: mark),
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

class _SmallLink extends StatelessWidget {
  const _SmallLink(this.label, this.onTap);

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TapArea(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Text(
          label,
          style: const TextStyle(fontSize: 13, color: Hue.accent),
        ),
      ),
    );
  }
}
