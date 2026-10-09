import 'dart:math';

import 'package:flutter/material.dart';

import '../charts/bar_scale.dart';
import '../charts/budget_bar.dart';
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
  int? _piece;
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
                    _piece = null;
                  }),
                ),
              ],
            ),
          ),
          _Summary(ledger: ledger, month: _month),
          const SizedBox(height: 14),
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
    final last = min(entries.length, (page + 1) * _perPage);
    final atToday = !sunday.isBefore(ledger.today);
    final from = '${monday.month} / ${monday.day}';
    final to = '${sunday.month} / ${sunday.day}';
    return [
      SectionHead(
        '每日紀錄',
        trailing: Text(
          '本週 TWD ${_m(groupDigits(weekSpent))}',
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
              foregroundColor: Hue.positive,
              minimumSize: const Size(44, 44),
            ),
            child: Text(
              last < entries.length
                  ? '還有 ${entries.length - last} 筆 ›'
                  : '‹ 回到前 $_perPage 筆',
            ),
          ),
        ),
      const Divider(),
    ];
  }

  List<Widget> _market() {
    final ledger = widget.ledger;
    final holdings = ledger.holdings;
    final change = ledger.dayChange;
    final before = ledger.investValue - change;
    final largest = holdings.fold(0, (m, h) => max(m, h.change.abs()));
    final today = ledger.today;
    final code = _holding;
    final picked = code == null ? null : ledger.holding(code);
    final pickedGain = picked == null
        ? ''
        : '${signed(picked.gain)}（${percentOf(picked.gain, picked.cost)}）';
    final rows = <Widget>[];
    for (var i = 0; i < holdings.length; i += 2) {
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _marketCell(holdings[i], largest)),
              const VerticalDivider(width: 14),
              Expanded(
                child: i + 1 < holdings.length
                    ? _marketCell(holdings[i + 1], largest)
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      );
    }
    return [
      Padding(
        padding: const EdgeInsets.only(top: 22, bottom: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '投資行情',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const Spacer(),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${today.month}/${today.day} 當日損益 ${_m(signed(change))}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: change < 0 ? Hue.negative : Hue.positive,
                  ),
                ),
                Text(
                  '示意行情 · ${percentOf(change, before)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: change < 0 ? Hue.negative : Hue.positive,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      Text(
        '投資市值 TWD ${_m(groupDigits(ledger.investValue))}',
        style: const TextStyle(fontSize: 13, color: Hue.muted),
      ),
      const SizedBox(height: 8),
      ...rows,
      if (picked != null)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text.rich(
            TextSpan(
              style: const TextStyle(fontSize: 13, color: Hue.muted),
              children: [
                TextSpan(
                  text: '${picked.name} ${picked.code}　',
                  style: const TextStyle(
                    color: Hue.ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                TextSpan(text: '市值 ${_m(groupDigits(picked.value))}　損益 '),
                TextSpan(
                  text: _m(pickedGain),
                  style: TextStyle(
                    color: picked.gain < 0 ? Hue.negative : Hue.positive,
                  ),
                ),
              ],
            ),
          ),
        ),
      const SizedBox(height: 8),
      const Divider(),
    ];
  }

  Widget _marketCell(Holding h, int largest) {
    final picked = h.code == _holding;
    return InkWell(
      onTap: () => setState(() => _holding = picked ? null : h.code),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: picked ? Hue.selected.withValues(alpha: 0.6) : null,
          border: const Border(bottom: BorderSide(color: Hue.line)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    h.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _m(signed(h.change)),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: h.change < 0 ? Hue.negative : Hue.positive,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                SizedBox(
                  width: 46,
                  child: Text(
                    h.code,
                    style: const TextStyle(fontSize: 10, color: Hue.muted),
                  ),
                ),
                Expanded(
                  child: AxisBar(
                    value: h.change,
                    largest: largest,
                    scale: _scale,
                    axis: 0.3,
                    height: 6,
                  ),
                ),
              ],
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
              'TWD ${_m(groupDigits(amount))}',
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
                      text: 'TWD ${_m(groupDigits(limit - spent))}',
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
        pace: _pace(year, month),
        selected: piece,
        onSelect: (index) => setState(() => _piece = index),
      ),
      const SizedBox(height: 8),
      const Divider(),
    ];
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
  static const _shades = [
    Color(0xFF78906D),
    Color(0xFFB97D61),
    Color(0xFF6E929B),
    Color(0xFFB19A56),
    Color(0xFF927EAA),
    Color(0xFFB77380),
    Color(0xFF67857D),
    Color(0xFFA58368),
    Color(0xFF858AA8),
    Color(0xFFA1A56A),
    Color(0xFF879D92),
    Color(0xFFA28595),
  ];

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
          if (h.value > 0) (h.code, h.name, h.value),
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
          'TWD ${_m(groupDigits(shownAmount))}',
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
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          group == null ? '點選區塊看金額，再點一次展開明細' : '再點一次選取的區塊回到資產',
          style: const TextStyle(fontSize: 11, color: Hue.muted),
        ),
      ),
      const SizedBox(height: 10),
      const Divider(),
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
          Text(scope, style: const TextStyle(fontSize: 13, color: Hue.muted)),
          const Spacer(),
          const Text('結餘 ', style: TextStyle(fontSize: 13, color: Hue.muted)),
          Text(
            'TWD ${_m(groupDigits(left))}',
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
              'TWD ${_m(groupDigits(shown.income))}',
              Hue.positive,
            ),
          ),
          Expanded(
            child: _Dotted(
              '支出',
              'TWD ${_m(groupDigits(shown.expense))}',
              Hue.negative,
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
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
            'TWD ${_m(groupDigits(shown.worth))}',
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

/// 本月收入、本月支出、其中股息、本月結餘 in four columns.
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
    final items = [
      (Glyph.income, '本月收入', income, Hue.positive, false),
      (Glyph.payout, '本月支出', expense, Hue.negative, true),
      (
        Glyph.dividend,
        '其中股息',
        ledger.dividends(year, m),
        Hue.investment,
        false,
      ),
      (
        Glyph.wallet,
        '本月結餘',
        left,
        left < 0 ? Hue.negative : Hue.positive,
        true,
      ),
    ];
    return Row(
      children: [
        for (final (icon, label, amount, color, strong) in items)
          Expanded(
            child: Column(
              children: [
                IconBadge(icon, color, size: 34),
                const SizedBox(height: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    color: strong ? Hue.ink : Hue.muted,
                    fontWeight: strong ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    ledger.hidden ? '••••' : groupDigits(amount),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
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
    final upcoming = ledger.upcoming;
    final next = due.isNotEmpty
        ? due.first
        : upcoming.isEmpty
        ? null
        : upcoming.first;
    final today = ledger.today;
    final hidden = ledger.hidden;
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
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: due.isNotEmpty
                          ? '${due.length} 筆已到期'
                          : next == null
                          ? '沒有待扣款項目'
                          : '${upcoming.length} 筆即將扣款',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (next != null)
                      TextSpan(
                        text:
                            '　${today.month}/${next.day} ${next.name} '
                            '${hidden ? '••••' : groupDigits(next.amount)}',
                        style: const TextStyle(fontSize: 13, color: Hue.muted),
                      ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const GlyphIcon(Glyph.next, size: 18, color: Hue.muted),
          ],
        ),
      ),
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
              style: TextButton.styleFrom(foregroundColor: Hue.positive),
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

class _Dotted extends StatelessWidget {
  const _Dotted(this.label, this.value, this.color);

  final String label;
  final String value;
  final Color color;

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
            Text(label, style: const TextStyle(fontSize: 13, color: Hue.muted)),
          ],
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: color,
            ),
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: Text(
          label,
          style: const TextStyle(fontSize: 12, color: Hue.positive),
        ),
      ),
    );
  }
}
