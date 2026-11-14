import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/charts/donut.dart';
import '../../../core/charts/treemap.dart';

import 'package:flutter/rendering.dart' show RenderRepaintBoundary;

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

part 'report_figures.dart';
part 'report_blocks.dart';

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

  /// The tab shown: 收支, 分類, 比較 or 習慣.
  var _tab = 0;

  static const _tabs = [
    (Glyph.reports, '收支', Palette.blue),
    (Glyph.grid, '分類', Palette.rose),
    (Glyph.swap, '比較', Palette.indigo),
    (Glyph.calendar, '習慣', Palette.orange),
  ];

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
            CenterHeader(
              '財務報表',
              onBack: widget.nav.back,
              actions: [
                ?switch (widget.nav.saveFile) {
                  final save? => IconButton(
                    tooltip: '存成圖片',
                    onPressed: () => _savePicture(save, period),
                    icon: const GlyphIcon(Glyph.download, size: 20),
                  ),
                  null => null,
                },
              ],
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
            // What 存成圖片 saves: the period's sums, on the page's own
            // background.
            RepaintBoundary(
              key: _picture,
              child: ColoredBox(
                color: Hue.paper,
                child: _Hero(
                  ledger: ledger,
                  income: income,
                  expense: expense,
                  dividends: report.dividends,
                  lastExpense: report.lastExpense,
                  until: to.isAfter(today) ? today : null,
                ),
              ),
            ),
            const SizedBox(height: 12),
            BigSegments(
              items: _tabs,
              selected: _tab,
              onChanged: (i) => setState(() => _tab = i),
            ),
            const SizedBox(height: 12),
            switch (_tab) {
              0 => Sections([
                for (final w in _flow(
                  report,
                  buckets,
                  peak,
                  byMonth,
                  readout,
                  selected,
                ))
                  if (w is! SizedBox) w,
              ]),
              1 => Sections([
                if (biggest != null && expense > 0)
                  TitleRow(
                    '最大分類 $biggest ${report.spending[biggest]! * 100 ~/ expense}%',
                    trailing: const Text('點分類看紀錄', style: mutedSmall),
                  ),
                section(null, _mix(report)),
                if (biggest == null)
                  const EmptyState(
                    glyph: Glyph.grid,
                    color: Hue.faint,
                    message: '這段時間沒有紀錄',
                  ),
              ], gap: 0),
              2 => CompareSection(ledger: ledger, period: period),
              _ => Sections([
                if (period.span == ReportSpan.year)
                  section(null, _summary(report)),
                section(null, _highlights(report)),
                section(null, _weekdays(report)),
                section(null, _merchants(report)),
                section(null, _tags(report)),
                if (report.count == 0)
                  const EmptyState(
                    glyph: Glyph.calendar,
                    color: Hue.faint,
                    message: '這段時間沒有紀錄',
                  ),
              ]),
            },
          ],
        );
      },
    );
  }

  /// 收支: the average a week or month against last year, the dearest
  /// stretch, and the chart of spending, income and net worth with what
  /// the period's net worth did.
  List<Widget> _flow(
    _Report report,
    List<PeriodBucket> buckets,
    int? peak,
    bool byMonth,
    PeriodBucket? readout,
    int? selected,
  ) {
    final ledger = widget.ledger;
    final change = report.worthNow - report.worthBefore;
    return [
      CardGrid(gap: 10, [
        _Block(
          glyph: Glyph.calendar,
          color: _tabs[0].$3,
          label: byMonth ? '平均每月支出' : '平均每週支出',
          value: ledger.orDots(groupDigits(report.perStretch)),
          sub: _versus(report.expense, report.lastExpense),
        ),
        _Block(
          glyph: Glyph.payout,
          color: _tabs[3].$3,
          label: '支出最高',
          value: peak == null ? '—' : _stretchName(buckets[peak]),
          sub: peak == null
              ? ''
              : ledger.orDots(groupDigits(buckets[peak].expense)),
        ),
      ]),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        decoration: BoxDecoration(
          color: Hue.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: Hue.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Expanded(
                  child: Text(
                    '收支與淨資產',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
                LegendKey(Hue.negative, '支出'),
                SizedBox(width: 8),
                LegendKey(Hue.positive, '收入'),
                SizedBox(width: 8),
                LegendKey(Hue.investment, '淨資產', line: true),
              ],
            ),
            const SizedBox(height: 10),
            PeriodBars(
              buckets: buckets,
              worth: report.worth,
              selected: selected,
              onSelect: (i) => setState(() => _stretch = i),
            ),
            const SizedBox(height: 8),
            _Readout(
              ledger: ledger,
              label: readout == null ? '整段期間' : _stretchName(readout),
              income: readout?.income ?? report.income,
              expense: readout?.expense ?? report.expense,
              worth: readout == null || selected == null
                  ? report.worthNow
                  : report.worth.elementAtOrNull(selected),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '淨資產 期初 ${ledger.orDots(groupDigits(report.worthBefore))}'
                    ' → 期末 ${ledger.orDots(groupDigits(report.worthNow))}',
                    style: mutedSmall,
                  ),
                ),
                Text(
                  ledger.orDots(signed(change)),
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: change < 0 ? Hue.negative : Hue.positive,
                  ),
                ),
              ],
            ),
            if (ledger.holdings.isNotEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('過去的股票市值以今日股價估算', style: mutedSmall),
              ),
          ],
        ),
      ),
    ];
  }

  /// 習慣's two highlights: the day of the week spent most on, and the
  /// merchant gone to most.
  List<Widget> _highlights(_Report report) {
    final ledger = widget.ledger;
    final days = report.weekdays;
    final most = days.fold(0, max);
    final merchant = report.merchants.isEmpty ? null : report.merchants.first;
    if (most <= 0 && merchant == null) return const [];
    return [
      CardGrid(gap: 10, [
        _Block(
          glyph: Glyph.calendar,
          color: Hue.negative,
          label: '花最多的一天',
          value: most <= 0 ? '—' : '週${weekdayNames[days.indexOf(most)]}',
          sub: most <= 0 ? '' : '這段時間共 ${ledger.orDots(groupDigits(most))}',
        ),
        _Block(
          glyph: Glyph.store,
          color: Hue.positive,
          label: '最常去',
          value: merchant?.$1 ?? '—',
          sub: merchant == null
              ? ''
              : '${merchant.$2} 次 · 每次約 '
                    '${ledger.orDots(groupDigits(merchant.$3 ~/ merchant.$2))}',
        ),
      ]),
    ];
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
      const TitleRow('年度總結'),
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
    // As many of the largest as get a block big enough to read, the rest
    // together: on a small phone or with large text, fewer blocks.
    List<(String, int, int?)> blocksOf(int count) {
      final rest = names
          .skip(count)
          .fold(0, (sum, n) => sum + (spending[n] ?? 0));
      return [
        for (final n in names.take(count))
          (n, spending[n] ?? 0, lastSpending[n]),
        if (rest > 0) ('其他', rest, null),
      ];
    }

    return [
      LayoutBuilder(
        builder: (context, box) {
          final scale = MediaQuery.textScalerOf(context).scale(1);
          final width = box.maxWidth;
          // What a block needs: its name with the share over its amount.
          final minWidth = 84 * scale;
          final minHeight = 56 * scale;
          final base = width * 0.82;
          var height = base;
          var blocks = blocksOf(names.length);
          var rects = <Rect>[];
          // Taller first, then fewer blocks: a category merged into 其他
          // only when no height up to half again more makes room for it.
          search:
          for (var count = min(7, names.length); count >= 1; count--) {
            blocks = blocksOf(count);
            for (final stretch in const [1.0, 1.2, 1.4, 1.6]) {
              height = base * stretch;
              rects = treemapLayout([
                for (final b in blocks) b.$2,
              ], Rect.fromLTWH(0, 0, width, height));
              if (rects.every(
                (r) => r.width - 8 >= minWidth && r.height - 8 >= minHeight,
              )) {
                break search;
              }
            }
          }
          return SizedBox(
            height: height,
            child: Stack(
              children: [
                for (final (i, (name, amount, last)) in blocks.indexed)
                  if (i < rects.length)
                    Positioned.fromRect(
                      rect: rects[i].deflate(4),
                      child: _CategoryBlock(
                        ledger: ledger,
                        category: name == '其他' && !spending.containsKey('其他')
                            ? Category('其他', 'other', Hue.faint)
                            : ledger.category(name),
                        amount: amount,
                        share: expense == 0 ? 0 : amount * 100 ~/ expense,
                        change: last == null || last == 0
                            ? null
                            : (amount - last) * 100 ~/ last,
                        large: i == 0,
                        onTap: name == '其他' && !spending.containsKey('其他')
                            ? null
                            : () => _showCategory(name),
                      ),
                    ),
              ],
            ),
          );
        },
      ),
      const Padding(
        padding: EdgeInsets.only(top: 6, left: 4),
        child: Text('▲▼ 是跟去年同期比', style: mutedSmall),
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
    final rows = report.merchants.take(4).toList();
    if (rows.isEmpty) return const [];
    final ledger = widget.ledger;
    final total = rows.fold(0, (sum, r) => sum + r.$3);
    return [
      TitleRow(
        '常去商家',
        trailing: Text(
          '這 ${rows.length} 家 · 合計 ${ledger.orDots(groupDigits(total))}',
          style: mutedSmall,
        ),
      ),
      Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
        decoration: BoxDecoration(
          color: Hue.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: Hue.cardShadow,
        ),
        child: Row(
          children: [
            Donut(
              size: 96,
              thickness: 20,
              slices: [
                for (final (i, r) in rows.indexed)
                  (r.$3, Hue.shades[(i + 2) % Hue.shades.length]),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                children: [
                  for (final (i, (name, count, amount)) in rows.indexed)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 5),
                            child: Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: Hue.shades[(i + 2) % Hue.shades.length],
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  '$count 次 · 每次約 '
                                  '${ledger.orDots(groupDigits(amount ~/ count))}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Hue.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            ledger.orDots(groupDigits(amount)),
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ],
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

  /// 星期: what was spent on each day of the week over the period, the
  /// heaviest day in the spending colour.
  List<Widget> _weekdays(_Report report) {
    final days = report.weekdays;
    final most = days.fold(0, max);
    if (most <= 0) return const [];
    final heaviest = days.indexOf(most);
    return [
      TitleRow('星期', trailing: const Text('虛線是每天平均', style: mutedSmall)),
      SoftPanel(
        color: Hue.white,
        padding: const EdgeInsets.fromLTRB(10, 14, 10, 10),
        child: Column(
          children: [
            SizedBox(
              height: 96,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (final (i, spent) in days.indexed)
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                              ),
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
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 96 * (days.fold(0, (s, d) => s + d) / 7 / most),
                    child: CustomPaint(
                      size: const Size(double.infinity, 1),
                      painter: _Dashes(Hue.muted),
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
    final counts = {for (final (tag, n, _) in ledger.tagStats) tag: n};
    return [
      const TitleRow('標籤'),
      CardGrid(columns: 3, gap: 8, [
        for (final (tag, amount) in rows.take(9))
          ColorCard(
            color: nameColor(tag),
            radius: 16,
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '#$tag',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: deepOf(nameColor(tag)),
                  ),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    ledger.orDots(groupDigits(amount)),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (counts[tag] case final n?)
                  Text(
                    '$n 筆',
                    style: const TextStyle(fontSize: 12, color: Hue.muted),
                  ),
              ],
            ),
          ),
      ]),
    ];
  }
}
