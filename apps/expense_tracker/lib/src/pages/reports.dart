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
import 'report_period.dart';

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
  late var _period = ReportPeriod.of(ReportSpan.year, widget.ledger.today);
  int? _stretch;
  String? _category;

  /// How many times the ledger has changed while the page is open. The
  /// sums are kept for a period and worked out again only after a change,
  /// so picking a stretch or a category does not add everything up anew.
  var _revision = 0;
  _Report? _report;
  (ReportPeriod, int)? _reportFor;

  DateTime get _today => widget.ledger.today;

  @override
  void initState() {
    super.initState();
    widget.ledger.addListener(_changed);
  }

  @override
  void didUpdateWidget(ReportsPage old) {
    super.didUpdateWidget(old);
    if (identical(old.ledger, widget.ledger)) return;
    old.ledger.removeListener(_changed);
    widget.ledger.addListener(_changed);
    _changed();
  }

  @override
  void dispose() {
    widget.ledger.removeListener(_changed);
    super.dispose();
  }

  /// The page draws again through its [ListenableBuilder]; here the kept
  /// sums are only marked as old.
  void _changed() => _revision++;

  _Report get _current {
    final key = (_period, _revision);
    final kept = _report;
    if (kept != null && _reportFor == key) return kept;
    _reportFor = key;
    return _report = _Report.of(widget.ledger, _period);
  }

  void _choose(int index) {
    setState(() {
      _stretch = null;
      _period = ReportPeriod.of(ReportSpan.values[index], _today);
    });
  }

  void _step(int by) {
    setState(() {
      _stretch = null;
      _period = _period.step(by);
    });
  }

  Future<void> _pickRange() async {
    final first = widget.ledger.firstDay;
    final from = _period.from;
    final to = _period.to;
    final start = from.isBefore(first) ? first : from;
    final end = to.isAfter(_today) ? _today : to;
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
      _stretch = null;
      _period = ReportPeriod.range(picked.start, picked.end);
    });
  }

  @override
  Widget build(BuildContext context) {
    final ledger = widget.ledger;
    return ListenableBuilder(
      listenable: ledger,
      builder: (context, _) {
        final report = _current;
        final period = _period;
        final today = report.today;
        final from = period.from;
        final to = period.to;
        final income = report.income;
        final expense = report.expense;
        final buckets = report.buckets;
        final peak = report.peak;
        final byMonth = period.span != ReportSpan.month;
        final biggest = report.names.isEmpty ? null : report.names.first;
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
              selected: period.span.index,
              onChanged: (i) {
                if (i == ReportSpan.custom.index) {
                  _pickRange();
                } else {
                  _choose(i);
                }
              },
            ),
            StepSwitch(
              label: period.title,
              previousLabel: '上一期',
              nextLabel: '下一期',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              onPrevious: from.isAfter(ledger.firstDay) ? () => _step(-1) : null,
              onNext: period.next.isAfter(today) ? null : () => _step(1),
              onLabelTap: _pickRange,
            ),
            BalanceHero(
              ledger: ledger,
              icon: Glyph.reports,
              label: to.isAfter(today)
                  ? '結餘 · 至 ${today.month}/${today.day}'
                  : '結餘',
              income: income,
              expense: expense,
              third: (
                Glyph.dividend,
                '其中股息',
                ledger.money(report.dividends),
                Hue.investment,
              ),
            ),
            TileRow([
              Tile(
                icon: Glyph.payout,
                label: byMonth ? '平均每月支出' : '平均每週支出',
                value: ledger.money(report.perStretch),
                sub: _versus(expense, report.lastExpense),
              ),
              Tile(
                icon: Glyph.calendar,
                label: '支出最高',
                value: peak == null ? '—' : _stretchName(buckets[peak]),
                sub: peak == null ? null : ledger.money(buckets[peak].expense),
              ),
            ]),
            TileRow([
              Tile(
                icon: Glyph.wallet,
                label: '淨資產變化',
                value: ledger.moneySigned(report.worthNow - report.worthBefore),
                valueColor: report.worthNow < report.worthBefore
                    ? Hue.negative
                    : Hue.positive,
                sub: '期末 ${ledger.money(report.worthNow)}',
              ),
              Tile(
                icon: Glyph.categories,
                label: '最大分類',
                value: biggest ?? '—',
                sub: biggest == null || expense == 0
                    ? null
                    : '占支出 ${report.spending[biggest]! * 100 ~/ expense}%',
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
              worth: report.worth,
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
              ledger: ledger,
              label: readout == null ? '整段期間' : _stretchName(readout),
              income: readout?.income ?? income,
              expense: readout?.expense ?? expense,
            ),
            ..._mix(report),
            ..._merchants(report),
            ..._tags(report),
          ],
        );
      },
    );
  }

  String _stretchName(PeriodBucket b) =>
      _period.span == ReportSpan.year ? '${b.label} 月' : b.label;

  /// 「較去年同期 +12.0%」, or nothing to compare with.
  String _versus(int now, int then) {
    if (then == 0) return '去年同期沒有紀錄';
    return '較去年同期 ${percentOf(now - then, then)}';
  }

  /// 分類: what each stretch's spending was made of, then every category
  /// with its share and the same time a year before.
  List<Widget> _mix(_Report report) {
    final names = report.names;
    if (names.isEmpty) return const [];
    final ledger = widget.ledger;
    final top = report.top;
    final spending = report.spending;
    final lastSpending = report.lastSpending;
    final expense = report.expense;
    final colors = [
      for (final name in top) ledger.category(name).color,
      if (names.length > top.length) Hue.faint,
    ];
    final picked = _category;
    final index = picked == null
        ? null
        : top.contains(picked)
        ? top.indexOf(picked)
        : top.length;
    return [
      const SectionHead(
        '分類',
        trailing: Text('對照去年同期', style: mutedSmall),
      ),
      MixBars(
        columns: report.columns,
        colors: colors,
        labels: [for (final (label, _, _) in report.stretches) label],
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
                ledger: ledger,
                category: ledger.category(name),
                amount: spending[name] ?? 0,
                last: lastSpending[name] ?? 0,
                share: expense == 0 ? 0 : (spending[name] ?? 0) / expense,
                largest: report.largest,
                picked: name == picked,
                onTap: () =>
                    setState(() => _category = name == picked ? null : name),
              ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _merchants(_Report report) {
    final rows = report.merchants;
    if (rows.isEmpty) return const [];
    final ledger = widget.ledger;
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
                          Text('$count 次', style: mutedSmall),
                        ],
                      ),
                    ),
                    Text(
                      ledger.money(amount),
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

  List<Widget> _tags(_Report report) {
    final rows = report.tags;
    if (rows.isEmpty) return const [];
    final ledger = widget.ledger;
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
                      text: ledger.money(amount),
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

/// Every sum the page shows for one period, worked out together. Entries
/// are read a month at a time from the ledger's index of months, so a
/// stretch costs only its own months rather than the whole book.
final class _Report {
  _Report._({
    required this.today,
    required this.stretches,
    required this.income,
    required this.expense,
    required this.dividends,
    required this.lastExpense,
    required this.buckets,
    required this.peak,
    required this.perStretch,
    required this.worthBefore,
    required this.worthNow,
    required this.worth,
    required this.spending,
    required this.lastSpending,
    required this.names,
    required this.top,
    required this.columns,
    required this.largest,
    required this.merchants,
    required this.tags,
  });

  factory _Report.of(Ledger ledger, ReportPeriod period) {
    final today = ledger.today;
    final from = period.from;
    final to = period.to;
    final until = to.isAfter(today) ? today : to;
    final stretches = period.stretches;
    final entries = _between(ledger, from, to);
    var income = 0;
    var expense = 0;
    var dividends = 0;
    for (final e in entries) {
      income += e.earning;
      expense += e.spending;
      dividends += e.dividendNet;
    }
    final before = _between(ledger, _yearBefore(from), _yearBefore(until));
    final lastExpense = before.fold(0, (sum, e) => sum + e.spending);
    final buckets = [
      for (final (label, a, b) in stretches)
        if (a.isAfter(today))
          PeriodBucket(label, 0, 0, ahead: true)
        else
          _bucket(label, _between(ledger, a, b)),
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
    // The ledger's own sum keeps the categories in the order it always
    // has, so equal amounts keep their places.
    final spending = ledger.spendingBetween(from, to);
    final lastSpending = _spendingOf(before);
    final names = spending.keys.toList()
      ..sort((a, b) => spending[b]!.compareTo(spending[a]!));
    final top = names.take(5).toList();
    List<int> column(DateTime a, DateTime b) {
      if (a.isAfter(today)) return const [];
      final part = _spendingOf(_between(ledger, a, b));
      final rest = part.entries
          .where((e) => !top.contains(e.key))
          .fold(0, (sum, e) => sum + e.value);
      return [for (final name in top) part[name] ?? 0, rest];
    }

    return _Report._(
      today: today,
      stretches: stretches,
      income: income,
      expense: expense,
      dividends: dividends,
      lastExpense: lastExpense,
      buckets: buckets,
      peak: peak,
      perStretch: passed.isEmpty ? 0 : expense ~/ passed.length,
      worthBefore: ledger.netWorthAt(from.subtract(const Duration(days: 1))),
      worthNow: ledger.netWorthAt(until),
      worth: [
        for (final (_, a, b) in stretches)
          a.isAfter(today)
              ? null
              : ledger.netWorthAt(b.isAfter(today) ? today : b),
      ],
      spending: spending,
      lastSpending: lastSpending,
      names: names,
      top: top,
      columns: names.isEmpty
          ? const []
          : [for (final (_, a, b) in stretches) column(a, b)],
      largest: names.fold(
        1,
        (m, n) => max(m, max(spending[n] ?? 0, lastSpending[n] ?? 0)),
      ),
      merchants: ledger.merchantsBetween(from, to).take(5).toList(),
      tags: ledger.tagsBetween(from, to),
    );
  }

  final DateTime today;
  final List<ReportStretch> stretches;
  final int income;
  final int expense;
  final int dividends;

  /// Spending over the same days a year before.
  final int lastExpense;
  final List<PeriodBucket> buckets;

  /// The stretch that spent the most, of those begun.
  final int? peak;
  final int perStretch;
  final int worthBefore;
  final int worthNow;

  /// Net worth at the end of each stretch; null for those to come.
  final List<int?> worth;

  /// Spending by category, now and a year before.
  final Map<String, int> spending;
  final Map<String, int> lastSpending;

  /// The categories spent on, largest first, and the five drawn in colour.
  final List<String> names;
  final List<String> top;

  /// Each stretch's spending in the [top] categories and the rest.
  final List<List<int>> columns;

  /// The scale of the category bars.
  final int largest;
  final List<(String, int, int)> merchants;
  final List<(String, int)> tags;

  /// The same day a year earlier, the 29th of February becoming the 28th.
  static DateTime _yearBefore(DateTime day) => DateTime.utc(
    day.year - 1,
    day.month,
    min(day.day, DateTime.utc(day.year - 1, day.month + 1, 0).day),
  );

  /// The entries from [from] to [to], read from those months only.
  static List<Entry> _between(Ledger ledger, DateTime from, DateTime to) => [
    for (
      var m = DateTime.utc(from.year, from.month);
      !m.isAfter(to);
      m = DateTime.utc(m.year, m.month + 1)
    )
      for (final e in ledger.entriesIn(m.year, m.month))
        if (!e.date.isBefore(from) && !e.date.isAfter(to)) e,
  ];

  static PeriodBucket _bucket(String label, List<Entry> entries) {
    var income = 0;
    var expense = 0;
    for (final e in entries) {
      income += e.earning;
      expense += e.spending;
    }
    return PeriodBucket(label, income, expense);
  }

  /// Spending by category name, split entries counted in their parts.
  static Map<String, int> _spendingOf(List<Entry> entries) {
    final totals = <String, int>{};
    for (final e in entries) {
      for (final (name, value) in e.spendingParts) {
        totals[name] = (totals[name] ?? 0) + value;
      }
    }
    return totals;
  }
}

/// A category of 分類: its mark, name and share, the amount and how it
/// moved against a year before, and two bars, this period over last
/// year's.
class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.ledger,
    required this.category,
    required this.amount,
    required this.last,
    required this.share,
    required this.largest,
    required this.picked,
    required this.onTap,
  });

  final Ledger ledger;
  final Category category;
  final int amount;
  final int last;
  final double share;
  final int largest;
  final bool picked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final change = last == 0 ? null : amount - last;
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
                      Text('${(share * 100).round()}%', style: mutedSmall),
                      const Spacer(),
                      Text(
                        ledger.money(amount),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  PairBars(
                    now: amount / largest,
                    then: last / largest,
                    color: category.color,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        '去年同期 ${ledger.money(last)}',
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: Hue.muted,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        change == null ? '新的支出' : percentOf(change, last),
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

/// The chosen stretch, or the whole period, in one line.
class _Readout extends StatelessWidget {
  const _Readout({
    required this.ledger,
    required this.label,
    required this.income,
    required this.expense,
  });

  final Ledger ledger;
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
          text: ledger.money(value),
          style: TextStyle(fontWeight: FontWeight.w700, color: color),
        ),
      ],
    ),
    style: const TextStyle(fontSize: 13),
  );
}
