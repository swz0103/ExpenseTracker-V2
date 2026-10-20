import 'dart:math';

import 'package:flutter/material.dart';

import '../charts/period_charts.dart';
import '../look/figures.dart';
import '../look/glyphs.dart';
import '../look/icons.dart';
import '../look/theme.dart';
import '../look/widgets.dart';
import '../model/ledger.dart';
import 'nav.dart';

/// How long a report runs.
enum _Span { month, quarter, year, custom }

/// One stretch of the chosen period: its label and first and last day.
typedef _Stretch = (String, DateTime, DateTime);

/// 財務報表: any stretch of time, not only a month. A month, quarter, year
/// or chosen range: what was left, how income and spending went stretch
/// by stretch, net worth, what the spending was made of against the same
/// time a year before, where it went and under which tags.
class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key, required this.ledger, required this.nav});

  final Ledger ledger;
  final Nav nav;

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  var _span = _Span.year;

  /// The first month of the period.
  late DateTime _start = DateTime.utc(widget.ledger.today.year);

  /// The last month of a chosen range.
  late DateTime _end = DateTime.utc(
    widget.ledger.today.year,
    widget.ledger.today.month,
  );
  int? _stretch;
  String? _category;

  DateTime get _today => widget.ledger.today;

  static DateTime _lastDay(DateTime month) =>
      DateTime.utc(month.year, month.month + 1, 0);

  /// The same day a year earlier, the 29th of February becoming the 28th.
  static DateTime _yearBefore(DateTime day) => DateTime.utc(
    day.year - 1,
    day.month,
    min(day.day, DateTime.utc(day.year - 1, day.month + 1, 0).day),
  );

  int get _months => switch (_span) {
    _Span.month => 1,
    _Span.quarter => 3,
    _Span.year => 12,
    _Span.custom =>
      (_end.year - _start.year) * 12 + _end.month - _start.month + 1,
  };

  DateTime get _from => _start;

  DateTime get _to =>
      _lastDay(DateTime.utc(_start.year, _start.month + _months - 1));

  String get _title {
    final y = _start.year;
    return switch (_span) {
      _Span.month => '$y 年 ${_start.month} 月',
      _Span.quarter => '$y 年 第 ${(_start.month - 1) ~/ 3 + 1} 季',
      _Span.year => '$y 年',
      _Span.custom => '$y/${_start.month} – ${_end.year}/${_end.month}',
    };
  }

  /// The stretches the charts are drawn by: weeks of a month, months of
  /// anything longer.
  List<_Stretch> get _stretches {
    if (_span == _Span.month) {
      final last = _lastDay(_start).day;
      return [
        for (var day = 1; day <= last; day += 7)
          (
            '$day 日',
            DateTime.utc(_start.year, _start.month, day),
            DateTime.utc(_start.year, _start.month, min(day + 6, last)),
          ),
      ];
    }
    return [
      for (var i = 0; i < _months; i++)
        (
          _span == _Span.year
              ? '${i + 1}'
              : '${DateTime.utc(_start.year, _start.month + i).month}月',
          DateTime.utc(_start.year, _start.month + i),
          _lastDay(DateTime.utc(_start.year, _start.month + i)),
        ),
    ];
  }

  void _choose(int index) {
    final today = _today;
    setState(() {
      _span = _Span.values[index];
      _stretch = null;
      _start = switch (_span) {
        _Span.month => DateTime.utc(today.year, today.month),
        _Span.quarter => DateTime.utc(
          today.year,
          (today.month - 1) ~/ 3 * 3 + 1,
        ),
        _Span.year => DateTime.utc(today.year),
        _Span.custom => DateTime.utc(today.year, today.month - 11),
      };
      _end = DateTime.utc(today.year, today.month);
    });
  }

  void _step(int by) {
    setState(() {
      _stretch = null;
      _start = DateTime.utc(_start.year, _start.month + by * _months);
      _end = DateTime.utc(_end.year, _end.month + by * _months);
    });
  }

  Future<void> _pickRange() async {
    final first = widget.ledger.firstDay;
    final start = _from.isBefore(first) ? first : _from;
    final end = _to.isAfter(_today) ? _today : _to;
    final picked = await showDateRangePicker(
      context: context,
      firstDate: first.isAfter(_today) ? _today : first,
      lastDate: _today,
      initialDateRange: start.isAfter(end)
          ? null
          : DateTimeRange(start: start, end: end),
      helpText: '選擇期間（以月為單位）',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _span = _Span.custom;
      _stretch = null;
      _start = DateTime.utc(picked.start.year, picked.start.month);
      _end = DateTime.utc(picked.end.year, picked.end.month);
    });
  }

  @override
  Widget build(BuildContext context) {
    final ledger = widget.ledger;
    return ListenableBuilder(
      listenable: ledger,
      builder: (context, _) {
        final today = _today;
        final from = _from;
        final to = _to;
        final until = to.isAfter(today) ? today : to;
        final stretches = _stretches;
        final (income, expense) = ledger.totalsBetween(from, to);
        final left = income - expense;
        final rate = income == 0 ? 0 : (left * 100 / income).round();
        final (_, lastExpense) = ledger.totalsBetween(
          _yearBefore(from),
          _yearBefore(until),
        );
        final buckets = [
          for (final (label, a, b) in stretches) _bucket(label, a, b),
        ];
        final passed = [
          for (final (i, b) in buckets.indexed)
            if (!b.ahead) i,
        ];
        final peak = passed.isEmpty
            ? null
            : passed.reduce(
                (a, b) => buckets[b].expense > buckets[a].expense ? b : a,
              );
        final elapsed = passed.length;
        final perStretch = elapsed == 0 ? 0 : expense ~/ elapsed;
        final byMonth = _span != _Span.month;
        final worthBefore = ledger.netWorthAt(
          from.subtract(const Duration(days: 1)),
        );
        final worthNow = ledger.netWorthAt(until);
        final spending = ledger.spendingBetween(from, to);
        final lastSpending = ledger.spendingBetween(
          _yearBefore(from),
          _yearBefore(until),
        );
        final names = spending.keys.toList()
          ..sort((a, b) => spending[b]!.compareTo(spending[a]!));
        final biggest = names.isEmpty ? null : names.first;
        final next = DateTime.utc(_start.year, _start.month + _months);
        final selected = _stretch;
        final readout = selected == null || selected >= buckets.length
            ? null
            : buckets[selected];
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          children: [
            PageHeader('財務報表', onBack: widget.nav.back),
            Segments(
              labels: const ['月', '季', '年', '自訂'],
              selected: _span.index,
              onChanged: (i) {
                if (i == _Span.custom.index) {
                  _pickRange();
                } else {
                  _choose(i);
                }
              },
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: '上一期',
                  onPressed: from.isAfter(ledger.firstDay)
                      ? () => _step(-1)
                      : null,
                  icon: const GlyphIcon(Glyph.back, size: 18),
                ),
                InkWell(
                  onTap: _pickRange,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 8,
                    ),
                    child: Text(
                      _title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '下一期',
                  onPressed: next.isAfter(today) ? null : () => _step(1),
                  icon: const GlyphIcon(Glyph.next, size: 18),
                ),
              ],
            ),
            Tile(
              hero: true,
              icon: Glyph.reports,
              label: to.isAfter(today)
                  ? '結餘 · 至 ${today.month}/${today.day}'
                  : '結餘',
              value: money(left),
              valueColor: left < 0 ? Hue.negative : Hue.positive,
              trailing: Pill('結餘率 $rate%'),
              child: TileStats([
                (Glyph.income, '收入', money(income), Hue.positive),
                (Glyph.payout, '支出', money(expense), Hue.negative),
                (
                  Glyph.dividend,
                  '其中股息',
                  money(ledger.dividendsBetween(from, to)),
                  Hue.investment,
                ),
              ]),
            ),
            TileRow([
              Tile(
                icon: Glyph.payout,
                label: byMonth ? '平均每月支出' : '平均每週支出',
                value: money(perStretch),
                sub: _versus(expense, lastExpense),
              ),
              Tile(
                icon: Glyph.calendar,
                label: '支出最高',
                value: peak == null ? '—' : _stretchName(buckets[peak]),
                sub: peak == null ? null : money(buckets[peak].expense),
              ),
            ]),
            TileRow([
              Tile(
                icon: Glyph.wallet,
                label: '淨資產變化',
                value: moneySigned(worthNow - worthBefore),
                valueColor: worthNow < worthBefore
                    ? Hue.negative
                    : Hue.positive,
                sub: '期末 ${money(worthNow)}',
              ),
              Tile(
                icon: Glyph.categories,
                label: '最大分類',
                value: biggest ?? '—',
                sub: biggest == null || expense == 0
                    ? null
                    : '占支出 ${spending[biggest]! * 100 ~/ expense}%',
              ),
            ]),
            SectionHead(
              '收支與淨資產',
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const LegendKey(Hue.positive, '收入'),
                  const SizedBox(width: 10),
                  const LegendKey(Hue.negative, '支出'),
                  const SizedBox(width: 10),
                  const LegendKey(Hue.investment, '淨資產', line: true),
                ],
              ),
            ),
            PeriodBars(
              buckets: buckets,
              worth: [
                for (final (_, a, b) in stretches)
                  a.isAfter(today)
                      ? null
                      : ledger.netWorthAt(b.isAfter(today) ? today : b),
              ],
              selected: selected,
              onSelect: (i) => setState(() => _stretch = i),
            ),
            if (ledger.holdings.isNotEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  '過去的股票市值以今日股價估算',
                  style: TextStyle(fontSize: 12.5, color: Hue.muted),
                ),
              ),
            const SizedBox(height: 8),
            _Readout(
              label: readout == null ? '整段期間' : _stretchName(readout),
              income: readout?.income ?? income,
              expense: readout?.expense ?? expense,
            ),
            ..._mix(stretches, names, spending, lastSpending, expense),
            ..._merchants(from, to),
            ..._tags(from, to),
          ],
        );
      },
    );
  }

  PeriodBucket _bucket(String label, DateTime from, DateTime to) {
    if (from.isAfter(_today)) return PeriodBucket(label, 0, 0, ahead: true);
    final (income, expense) = widget.ledger.totalsBetween(from, to);
    return PeriodBucket(label, income, expense);
  }

  String _stretchName(PeriodBucket b) =>
      _span == _Span.year ? '${b.label} 月' : b.label;

  /// 「較去年同期 +12%」, or nothing to compare with.
  String _versus(int now, int then) {
    if (then == 0) return '去年同期沒有紀錄';
    final change = ((now - then) * 100 / then).round();
    return '較去年同期 ${change > 0 ? '+' : ''}$change%';
  }

  /// 分類: what each stretch's spending was made of, then every category
  /// with its share and the same time a year before.
  List<Widget> _mix(
    List<_Stretch> stretches,
    List<String> names,
    Map<String, int> spending,
    Map<String, int> lastSpending,
    int expense,
  ) {
    if (names.isEmpty) return const [];
    final ledger = widget.ledger;
    final today = _today;
    final top = names.take(5).toList();
    final colors = [
      for (final name in top) ledger.category(name).color,
      if (names.length > top.length) Hue.faint,
    ];
    List<int> column(DateTime a, DateTime b) {
      if (a.isAfter(today)) return const [];
      final part = ledger.spendingBetween(a, b);
      final rest = part.entries
          .where((e) => !top.contains(e.key))
          .fold(0, (sum, e) => sum + e.value);
      return [for (final name in top) part[name] ?? 0, rest];
    }

    final columns = [for (final (_, a, b) in stretches) column(a, b)];
    final picked = _category;
    final index = picked == null
        ? null
        : top.contains(picked)
        ? top.indexOf(picked)
        : top.length;
    final largest = names.fold(
      1,
      (m, n) => max(m, max(spending[n] ?? 0, lastSpending[n] ?? 0)),
    );
    return [
      const SectionHead(
        '分類',
        trailing: Text(
          '對照去年同期',
          style: TextStyle(fontSize: 13, color: Hue.muted),
        ),
      ),
      MixBars(
        columns: columns,
        colors: colors,
        labels: [for (final (label, _, _) in stretches) label],
        selected: index,
      ),
      const SizedBox(height: 12),
      SoftPanel(
        color: Hue.white,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          children: [
            for (final name in names)
              _CategoryRow(
                category: ledger.category(name),
                amount: spending[name] ?? 0,
                last: lastSpending[name] ?? 0,
                share: expense == 0 ? 0 : (spending[name] ?? 0) / expense,
                largest: largest,
                picked: name == picked,
                onTap: () =>
                    setState(() => _category = name == picked ? null : name),
              ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _merchants(DateTime from, DateTime to) {
    final rows = widget.ledger.merchantsBetween(from, to).take(5).toList();
    if (rows.isEmpty) return const [];
    return [
      const SectionHead('常去商家'),
      SoftPanel(
        color: Hue.white,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        child: Column(
          children: [
            for (final (i, (name, count, amount)) in rows.indexed)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  border: i == 0
                      ? null
                      : const Border(top: BorderSide(color: Hue.line)),
                ),
                child: Row(
                  children: [
                    const IconBadge(Glyph.store, Hue.accent, size: 30),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name, style: const TextStyle(fontSize: 14)),
                          Text(
                            '$count 次',
                            style: const TextStyle(
                              fontSize: 13,
                              color: Hue.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      money(amount),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _tags(DateTime from, DateTime to) {
    final rows = widget.ledger.tagsBetween(from, to);
    if (rows.isEmpty) return const [];
    return [
      const SectionHead('標籤'),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final (tag, amount) in rows)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: Hue.tile,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '#$tag  ',
                      style: const TextStyle(color: Hue.accent),
                    ),
                    TextSpan(
                      text: money(amount),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                style: const TextStyle(fontSize: 13),
              ),
            ),
        ],
      ),
    ];
  }
}

/// A category of 分類: its mark, name and share, the amount and how it
/// moved against a year before, and two bars, this period over last
/// year's.
class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.category,
    required this.amount,
    required this.last,
    required this.share,
    required this.largest,
    required this.picked,
    required this.onTap,
  });

  final Category category;
  final int amount;
  final int last;
  final double share;
  final int largest;
  final bool picked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final change = last == 0 ? null : ((amount - last) * 100 / last).round();
    final tone = change == null || change == 0
        ? Hue.muted
        : change > 0
        ? Hue.negative
        : Hue.positive;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
        decoration: BoxDecoration(
          color: picked ? Hue.selected : null,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            IconBadge(iconFor(category.icon), category.color, size: 34),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        category.name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${(share * 100).round()}%',
                        style: const TextStyle(fontSize: 13, color: Hue.muted),
                      ),
                      const Spacer(),
                      Text(
                        money(amount),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  _Pair(
                    now: amount / largest,
                    then: last / largest,
                    color: category.color,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        '去年同期 ${money(last)}',
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: Hue.muted,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        change == null
                            ? '新的支出'
                            : '${change > 0 ? '+' : ''}$change%',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: tone,
                        ),
                      ),
                    ],
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

/// This period's bar in colour over last year's in grey.
class _Pair extends StatelessWidget {
  const _Pair({required this.now, required this.then, required this.color});

  final double now;
  final double then;
  final Color color;

  @override
  Widget build(BuildContext context) {
    Widget bar(double share, Color tint, double height) => ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(
        height: height,
        child: Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: share.clamp(0.02, 1.0),
            child: Container(color: tint),
          ),
        ),
      ),
    );
    return Column(
      children: [
        bar(now, color, 7),
        const SizedBox(height: 3),
        bar(then, Hue.faint.withValues(alpha: 0.6), 4),
      ],
    );
  }
}

/// The chosen stretch, or the whole period, in one line.
class _Readout extends StatelessWidget {
  const _Readout({
    required this.label,
    required this.income,
    required this.expense,
  });

  final String label;
  final int income;
  final int expense;

  @override
  Widget build(BuildContext context) {
    final left = income - expense;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Hue.tile,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 12),
          // Shrinks rather than overflows when the phone's text is large.
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Row(
                children: [
                  _figure('收', income, Hue.positive),
                  const SizedBox(width: 12),
                  _figure('支', expense, Hue.negative),
                  const SizedBox(width: 12),
                  _figure('餘', left, left < 0 ? Hue.negative : Hue.ink),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _figure(String label, int value, Color color) => Text.rich(
    TextSpan(
      children: [
        TextSpan(
          text: '$label ',
          style: const TextStyle(color: Hue.muted),
        ),
        TextSpan(
          text: money(value),
          style: TextStyle(fontWeight: FontWeight.w700, color: color),
        ),
      ],
    ),
    style: const TextStyle(fontSize: 13),
  );
}
