import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;

import '../../../core/charts/donut.dart';
import '../../../core/charts/period_charts.dart';
import '../../../core/look/figures.dart';
import '../../../core/look/glyphs.dart';
import '../../../core/look/icons.dart';
import '../../../core/look/theme.dart';
import '../../../core/look/widgets.dart';
import '../../../core/ledger/ledger.dart';
import '../../../core/nav.dart';
import '../../../core/ui/entry_tile.dart';
import 'compare_section.dart';
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

  /// The sums for a period, kept until the ledger's data changes (its
  /// [Ledger.revision] moves on) or the day turns: picking a stretch or a
  /// category, or hiding the amounts, does not add everything up anew.
  _Report? _report;
  (Ledger, ReportPeriod, int, DateTime)? _reportFor;

  DateTime get _today => widget.ledger.today;

  /// The part of the page 存成圖片 saves.
  final _picture = GlobalKey();

  /// Saves the period's sums and chart as a PNG, at three times the
  /// screen's size so it stays sharp when shared.
  Future<void> _savePicture(
    Future<bool> Function(String name, List<int> bytes) save,
    ReportPeriod period,
  ) async {
    final boundary =
        _picture.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return;
    try {
      final image = await boundary.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null) return;
      final saved = await save(
        '記帳本-報表-${period.title.replaceAll(RegExp(r'[ /]'), '')}.png',
        data.buffer.asUint8List(),
      );
      if (saved && mounted) showNote(context, '已存成圖片');
    } on Object catch (error) {
      if (mounted) showNote(context, '沒有存成圖片：$error');
    }
  }

  _Report get _current {
    final ledger = widget.ledger;
    final key = (ledger, _period, ledger.revision, ledger.today);
    final kept = _report;
    if (kept != null && _reportFor == key) return kept;
    _reportFor = key;
    return _report = _Report.of(ledger, _period);
  }

  /// Moves to [period]; the stretch and category picked in the last one
  /// mean nothing in it.
  void _show(ReportPeriod period) {
    setState(() {
      _stretch = null;
      _period = period;
    });
  }

  void _choose(int index) =>
      _show(ReportPeriod.of(ReportSpan.values[index], _today));

  void _step(int by) => _show(_period.step(by));

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
    _show(ReportPeriod.range(picked.start, picked.end));
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
            PageHeader(
              '財務報表',
              onBack: widget.nav.back,
              trailing: switch (widget.nav.saveFile) {
                final save? => IconButton(
                  tooltip: '存成圖片',
                  onPressed: () => _savePicture(save, period),
                  icon: const GlyphIcon(Glyph.download, size: 20),
                ),
                null => null,
              },
            ),
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
              onPrevious: from.isAfter(ledger.firstDay)
                  ? () => _step(-1)
                  : null,
              onNext: period.next.isAfter(today) ? null : () => _step(1),
              onLabelTap: _pickRange,
              labelHint: '選擇期間',
            ),
            // What 存成圖片 saves: the period's sums and its chart, on the
            // page's own background.
            RepaintBoundary(
              key: _picture,
              child: ColoredBox(
                color: Hue.paper,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
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
                        sub: peak == null
                            ? null
                            : ledger.money(buckets[peak].expense),
                      ),
                    ]),
                    TileRow([
                      Tile(
                        icon: Glyph.wallet,
                        label: '淨資產變化',
                        value: ledger.moneySigned(
                          report.worthNow - report.worthBefore,
                        ),
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
                  ],
                ),
              ),
            ),
            CompareSection(ledger: ledger, period: period),
            if (period.span == ReportSpan.year) ..._summary(report),
            ..._mix(report),
            ..._weekdays(report),
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

  /// 年度總結: the year in a few lines.
  List<Widget> _summary(_Report report) {
    final ledger = widget.ledger;
    final income = report.income;
    final kept = income - report.expense;
    final biggest = report.biggestSpend;
    final busiest = report.peak == null ? null : report.buckets[report.peak!];
    final merchant = report.merchants.isEmpty ? null : report.merchants.first;
    final lines = <(String, String)>[
      (
        '存下',
        income <= 0
            ? ledger.moneySigned(kept)
            : '${ledger.moneySigned(kept)}（收入的 ${(kept * 100 / income).round()}%）',
      ),
      ('記帳', '${report.days} 天、${report.count} 筆'),
      if (busiest != null)
        ('花最多的月份', '${busiest.label} 月 ${ledger.money(busiest.expense)}'),
      if (biggest != null)
        (
          '最大一筆支出',
          '${biggest.date.month}/${biggest.date.day} ${biggest.title} '
              '${ledger.money(biggest.spending)}',
        ),
      if (merchant != null) ('最常去', '${merchant.$1}（${merchant.$2} 次）'),
    ];
    return [
      const SectionHead('年度總結'),
      SoftPanel(
        color: Hue.white,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        child: Column(
          children: [
            for (final (i, (label, value)) in lines.indexed)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: i == 0 ? null : ruleAbove,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 96, child: Text(label, style: mutedSmall)),
                    Expanded(
                      child: Text(
                        value,
                        textAlign: TextAlign.end,
                        style: const TextStyle(fontWeight: FontWeight.w600),
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

  /// 分類: every category ranked by what was spent, against the same time
  /// a year before; each opens its entries.
  List<Widget> _mix(_Report report) {
    final names = report.names;
    if (names.isEmpty) return const [];
    final ledger = widget.ledger;
    final spending = report.spending;
    final lastSpending = report.lastSpending;
    final expense = report.expense;
    // The five largest in their colours, the rest together in grey.
    final top = names.take(5).toList();
    final rest = names.skip(5).fold(0, (sum, n) => sum + (spending[n] ?? 0));
    return [
      const SectionHead('分類', trailing: Text('點分類看紀錄', style: mutedSmall)),
      SoftPanel(
        color: Hue.white,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 10, 8, 6),
              child: Row(
                children: [
                  Donut(
                    size: 124,
                    thickness: 16,
                    slices: [
                      for (final n in top)
                        (spending[n] ?? 0, ledger.category(n).color),
                      if (rest > 0) (rest, Hue.faint),
                    ],
                    center: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('支出', style: mutedSmall),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            ledger.money(expense),
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final n in top)
                          _Share(
                            color: ledger.category(n).color,
                            name: n,
                            share: expense == 0
                                ? 0
                                : (spending[n] ?? 0) / expense,
                          ),
                        if (rest > 0)
                          _Share(
                            color: Hue.faint,
                            name: '其他',
                            share: expense == 0 ? 0 : rest / expense,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            for (final name in names)
              _CategoryRow(
                ledger: ledger,
                category: ledger.category(name),
                amount: spending[name] ?? 0,
                last: lastSpending[name] ?? 0,
                share: expense == 0 ? 0 : (spending[name] ?? 0) / expense,
                largest: report.largest,
                alone: names.length == 1,
                onTap: () => _showCategory(name),
              ),
          ],
        ),
      ),
    ];
  }

  /// The period's entries spent under [name], in a sheet; each opens.
  Future<void> _showCategory(String name) {
    final ledger = widget.ledger;
    final period = _period;
    final entries = [
      for (final e in _Report._between(ledger, period.from, period.to))
        if (e.spendingParts.any((p) => p.$1 == name)) e,
    ]..sort((a, b) => b.date.compareTo(a.date));
    final total = entries.fold(
      0,
      (sum, e) =>
          sum +
          e.spendingParts
              .where((p) => p.$1 == name)
              .fold(0, (s, p) => s + p.$2),
    );
    return showSheet<void>(
      context,
      (context) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Text(
              name,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            Text(
              '${period.title} · ${entries.length} 筆 · ${ledger.money(total)}',
              textAlign: TextAlign.center,
              style: mutedSmall,
            ),
            const SizedBox(height: 12),
            SoftPanel(
              color: Hue.white,
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Column(
                children: [
                  for (final e in entries)
                    EntryRow(
                      ledger: ledger,
                      entry: e,
                      onOpen: (entry) {
                        Navigator.of(context).pop();
                        widget.nav.showEntry(entry);
                      },
                      divider: !identical(e, entries.last),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _merchants(_Report report) {
    final rows = report.merchants;
    if (rows.isEmpty) return const [];
    final ledger = widget.ledger;
    final most = rows.fold(1, (m, r) => max(m, r.$3));
    return [
      const SectionHead('常去商家'),
      SoftPanel(
        color: Hue.white,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Column(
          children: [
            for (final (name, count, amount) in rows)
              _BarLine(
                lead: const IconBadge(Glyph.store, Hue.accent, size: 30),
                name: name,
                note: '$count 次',
                amount: ledger.money(amount),
                share: amount / most,
                color: Hue.accent,
              ),
          ],
        ),
      ),
    ];
  }

  /// 星期: what was spent on each day of the week over the period, the
  /// heaviest day in the spending colour.
  List<Widget> _weekdays(_Report report) {
    final days = report.weekdays;
    final most = days.fold(0, max);
    if (most <= 0) return const [];
    final heaviest = days.indexOf(most);
    return [
      SectionHead(
        '星期',
        trailing: Text('週${weekdayNames[heaviest]}花最多', style: mutedSmall),
      ),
      SoftPanel(
        color: Hue.white,
        padding: const EdgeInsets.fromLTRB(10, 14, 10, 10),
        child: Column(
          children: [
            SizedBox(
              height: 96,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final (i, spent) in days.indexed)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: FractionallySizedBox(
                          heightFactor: spent <= 0
                              ? 0.03
                              : max(spent / most, 0.06),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: i == heaviest
                                  ? Hue.negative
                                  : softOf(Hue.negative),
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                for (final (i, name) in weekdayNames.indexed)
                  Expanded(
                    child: Text(
                      name,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: i == heaviest
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: i == heaviest ? Hue.negative : Hue.muted,
                      ),
                    ),
                  ),
              ],
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
    final most = rows.fold(1, (m, r) => max(m, r.$2));
    return [
      const SectionHead('標籤'),
      SoftPanel(
        color: Hue.white,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Column(
          children: [
            for (final (tag, amount) in rows)
              _BarLine(
                name: '#$tag',
                amount: ledger.money(amount),
                share: amount / most,
                color: Hue.investment,
              ),
          ],
        ),
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
    required this.largest,
    required this.merchants,
    required this.tags,
    required this.count,
    required this.days,
    required this.biggestSpend,
    required this.weekdays,
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
    Entry? biggest;
    final days = <DateTime>{};
    final weekdays = List.filled(7, 0);
    for (final e in entries) {
      income += e.earning;
      expense += e.spending;
      weekdays[e.date.weekday - 1] += e.spending;
      dividends += e.dividendNet;
      days.add(e.date);
      if (e.type == EntryType.expense &&
          (biggest == null || e.spending > biggest.spending)) {
        biggest = e;
      }
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
      largest: names.fold(
        1,
        (m, n) => max(m, max(spending[n] ?? 0, lastSpending[n] ?? 0)),
      ),
      merchants: ledger.merchantsBetween(from, to).take(5).toList(),
      tags: ledger.tagsBetween(from, to),
      count: entries.length,
      days: days.length,
      biggestSpend: biggest,
      weekdays: weekdays,
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

  /// The categories spent on, largest first.
  final List<String> names;

  /// The scale of the category bars.
  final int largest;
  final List<(String, int, int)> merchants;
  final List<(String, int)> tags;

  /// How many entries, on how many days.
  final int count;
  final int days;

  /// The largest single spending.
  final Entry? biggestSpend;

  /// Spending on each day of the week, Monday first.
  final List<int> weekdays;

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
    required this.alone,
    required this.onTap,
  });

  final Ledger ledger;
  final Category category;
  final int amount;
  final int last;
  final double share;
  final int largest;

  /// Whether this is the only category: its share is then all of it, and
  /// a bar is drawn only to set it against last year.
  final bool alone;
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
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(14)),
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
                      if (!alone) ...[
                        const SizedBox(width: 6),
                        Text('${(share * 100).round()}%', style: mutedSmall),
                      ],
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
                  if (!alone || last > 0) ...[
                    const SizedBox(height: 6),
                    PairBars(
                      now: amount / largest,
                      then: last / largest,
                      color: category.color,
                    ),
                  ],
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

/// A slice of the ring of 分類: its colour, name and share.
class _Share extends StatelessWidget {
  const _Share({required this.color, required this.name, required this.share});

  final Color color;
  final String name;
  final double share;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13),
          ),
        ),
        Text('${(share * 100).round()}%', style: mutedSmall),
      ],
    ),
  );
}

/// A line of a ranked list: a name over a bar as long as its share of
/// the largest, and the amount.
class _BarLine extends StatelessWidget {
  const _BarLine({
    required this.name,
    required this.amount,
    required this.share,
    required this.color,
    this.lead,
    this.note,
  });

  final Widget? lead;
  final String name;
  final String? note;
  final String amount;
  final double share;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final side = lead;
    final extra = note;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          if (side != null) ...[side, const SizedBox(width: 10)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                    if (extra != null) ...[
                      const SizedBox(width: 6),
                      Text(extra, style: mutedSmall),
                    ],
                    const Spacer(),
                    Text(
                      amount,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: SizedBox(
                    height: 6,
                    child: ColoredBox(
                      color: Hue.track,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: share.clamp(0.02, 1.0),
                          heightFactor: 1,
                          child: ColoredBox(color: color),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
