part of 'reports.dart';

class _ReportsPageState extends State<ReportsPage> {
  late var _period = ReportPeriod.of(ReportSpan.year, widget.ledger.today);
  int? _stretch;

  /// The tab shown: 收支, 分類, 比較 or 習慣.
  var _tab = 0;

  static const _tabs = [
    (Glyph.reports, '收支', Palette.blue),
    (Glyph.grid, Words.category, Palette.rose),
    (Glyph.swap, '比較', Palette.indigo),
    (Glyph.calendar, '習慣', Palette.orange),
  ];

  /// The sums for a period, kept until the ledger's data changes (its
  /// [Ledger.revision] moves on) or the day turns: picking a stretch or a
  /// category, or hiding the amounts, does not add everything up anew.
  Report? _report;
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
      ErrorLog.instance.record('存成圖片', error);
      if (mounted) showNote(context, '沒有存成圖片：${ErrorLog.describe(error)}');
    }
  }

  Report get _current {
    final ledger = widget.ledger;
    final key = (ledger, _period, ledger.revision, ledger.today);
    final kept = _report;
    if (kept != null && _reportFor == key) return kept;
    _reportFor = key;
    return _report = _reportOf(ledger, _period);
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
    final first = widget.ledger.reportService.firstDay;
    final from = _period.from;
    final to = _period.to;
    final start = from.isBefore(first) ? first : from;
    final end = to.isAfter(_today) ? _today : to;
    final picked = await pickDateRange(
      context,
      first: first.isAfter(_today) ? _today : first,
      last: _today,
      initial: start.isAfter(end)
          ? null
          : DateTimeRange(start: start, end: end),
      title: '報表期間',
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
        return HeadedList(
          padding: const EdgeInsets.fromLTRB(Space.s5, 0, Space.s5, Space.s4),
          header: _header(period),
          children: [
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
              style: const TextStyle(
                fontSize: TextSize.title,
                fontWeight: FontWeight.w700,
              ),
              onPrevious: from.isAfter(ledger.reportService.firstDay)
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
                color: AppColors.paper,
                child: ReportHero(
                  ledger: ledger,
                  income: report.income,
                  expense: report.expense,
                  dividends: report.dividends,
                  lastExpense: report.lastExpense,
                  until: to.isAfter(today) ? today : null,
                ),
              ),
            ),
            const SizedBox(height: Space.s3),
            BigSegments(
              items: _tabs,
              selected: _tab,
              onChanged: (i) => setState(() => _tab = i),
            ),
            const SizedBox(height: Space.s3),
            _tabBody(report, period),
          ],
        );
      },
    );
  }

  /// 財務報表's header, with 存成圖片 where the phone can save files.
  Widget _header(ReportPeriod period) => CenterHeader(
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
  );

  /// The tab chosen under the hero: 收支, 分類, 比較 or 習慣.
  Widget _tabBody(Report report, ReportPeriod period) {
    final ledger = widget.ledger;
    final expense = report.expense;
    final buckets = _bars(report);
    final byMonth = period.span != ReportSpan.month;
    final biggest = report.names.isEmpty ? null : report.names.first;
    final selected = _stretch;
    final readout = selected == null || selected >= buckets.length
        ? null
        : buckets[selected];
    return switch (_tab) {
      0 => Sections([
        for (final w in _flow(
          report,
          buckets,
          report.peak,
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
            color: AppColors.faint,
            message: '這段時間沒有紀錄',
          ),
      ], gap: 0),
      2 => CompareSection(ledger: ledger, period: period),
      _ => Sections([
        if (period.span == ReportSpan.year) section(null, _summary(report)),
        section(null, highlightsSection(widget.ledger, report)),
        section(null, weekdaysSection(report)),
        section(null, merchantsSection(widget.ledger, report)),
        section(null, tagsSection(widget.ledger, report)),
        if (report.count == 0)
          const EmptyState(
            glyph: Glyph.calendar,
            color: AppColors.faint,
            message: '這段時間沒有紀錄',
          ),
      ]),
    };
  }

  /// 收支: the average a week or month against last year, the dearest
  /// stretch, and the chart of spending, income and net worth with what
  /// the period's net worth did.
  List<Widget> _flow(
    Report report,
    List<PeriodBucket> buckets,
    int? peak,
    bool byMonth,
    PeriodBucket? readout,
    int? selected,
  ) {
    final ledger = widget.ledger;
    return [
      CardGrid(gap: 10, [
        ReportBlock(
          glyph: Glyph.calendar,
          color: _tabs[0].$3,
          label: byMonth ? '平均每月支出' : '平均每週支出',
          value: ledger.orDots(groupDigits(report.perStretch)),
          sub: _versus(report.expense, report.lastExpense),
        ),
        ReportBlock(
          glyph: Glyph.payout,
          color: _tabs[3].$3,
          label: '支出最高',
          value: peak == null ? '—' : _stretchName(buckets[peak]),
          sub: peak == null
              ? ''
              : ledger.orDots(groupDigits(buckets[peak].expense)),
        ),
      ]),
      const SizedBox(height: Space.s3),
      _flowChart(report, buckets, readout, selected),
    ];
  }

  /// 收支與淨資產: spending, income and net worth stretch by stretch, the
  /// figures of the stretch picked, and what the period's net worth did.
  Widget _flowChart(
    Report report,
    List<PeriodBucket> buckets,
    PeriodBucket? readout,
    int? selected,
  ) {
    final ledger = widget.ledger;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        Space.s4,
        Space.s4,
        Space.s4,
        Space.s3,
      ),
      decoration: BoxDecoration(
        color: AppColors.group,
        borderRadius: BorderRadius.circular(Radii.largeIncreased),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _flowKeys,
          const SizedBox(height: Space.s2),
          PeriodBars(
            buckets: buckets,
            worth: report.worth,
            selected: selected,
            onSelect: (i) => setState(() => _stretch = i),
          ),
          const SizedBox(height: Space.s2),
          ReportReadout(
            ledger: ledger,
            label: readout == null ? '整段期間' : _stretchName(readout),
            income: readout?.income ?? report.income,
            expense: readout?.expense ?? report.expense,
            worth: readout == null || selected == null
                ? report.worthNow
                : report.worth.elementAtOrNull(selected),
          ),
          const SizedBox(height: Space.s2),
          ..._worthChange(report),
        ],
      ),
    );
  }

  /// The title of 收支與淨資產 and the keys of its chart.
  static const _flowKeys = Row(
    children: [
      Expanded(
        child: OneLine(
          '收支與淨資產',
          style: TextStyle(
            fontSize: TextSize.title,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      LegendKey(AppColors.negative, Words.expense),
      SizedBox(width: Space.s2),
      LegendKey(AppColors.positive, Words.income),
      SizedBox(width: Space.s2),
      LegendKey(AppColors.investment, '淨資產', line: true),
    ],
  );

  /// The period's net worth at its start and end and the change, and
  /// that past stock values are estimated at today's prices.
  List<Widget> _worthChange(Report report) {
    final ledger = widget.ledger;
    final change = report.worthNow - report.worthBefore;
    return [
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
              color: AppColors.ofChange(change),
            ),
          ),
        ],
      ),
      if (ledger.holdings.all.isNotEmpty)
        const Padding(
          padding: EdgeInsets.only(top: Space.s1),
          child: Text('過去的股票市值以今日股價估算', style: mutedSmall),
        ),
    ];
  }

  /// The report's stretches as the chart takes them.
  static List<PeriodBucket> _bars(Report report) => [
    for (final b in report.buckets)
      PeriodBucket(b.label, b.income, b.expense, ahead: b.ahead),
  ];

  String _stretchName(PeriodBucket b) =>
      _period.span == ReportSpan.year ? '${b.label} 月' : b.label;

  /// 「較去年同期 +12.0%」, or nothing to compare with.
  String _versus(int now, int then) {
    if (then == 0) return '去年同期沒有紀錄';
    return '較去年同期 ${percentOf(now - then, then)}';
  }

  /// 年度總結: the year in a few lines.
  List<Widget> _summary(Report report) {
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
          '${formatMd(biggest.date)} ${biggest.title} '
              '${ledger.money(biggest.spending)}',
        ),
      if (merchant != null) ('最常去', '${merchant.$1}（${merchant.$2} 次）'),
    ];
    return [
      const TitleRow('年度總結'),
      GroupBox(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.s4,
          vertical: Space.s1,
        ),
        child: Column(
          children: [
            for (final (i, (label, value)) in lines.indexed)
              Container(
                padding: const EdgeInsets.symmetric(vertical: Space.s2),
                decoration: i == 0 ? null : ruleAbove,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 96,
                      child: OneLine(label, style: mutedSmall),
                    ),
                    Expanded(
                      child: OneLine(
                        value,
                        alignment: AlignmentDirectional.centerEnd,
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
  List<Widget> _mix(Report report) {
    if (report.names.isEmpty) return const [];
    return [
      LayoutBuilder(builder: (context, box) => _treemap(context, box, report)),
      const Padding(
        padding: EdgeInsets.only(top: Space.s2, left: Space.s1),
        child: Text('▲▼ 是跟去年同期比', style: mutedSmall),
      ),
    ];
  }

  /// The [count] largest categories of [report], with what each spent a
  /// year before, and the rest together as 其他.
  static List<(String, int, int?)> _blocksOf(Report report, int count) {
    final names = report.names;
    final spending = report.spending;
    final rest = names
        .skip(count)
        .fold(0, (sum, n) => sum + (spending[n] ?? 0));
    return [
      for (final n in names.take(count))
        (n, spending[n] ?? 0, report.lastSpending[n]),
      if (rest > 0) ('其他', rest, null),
    ];
  }

  /// The categories of [report] as blocks sized by what they spent, [box]
  /// wide. As many of the largest as get a block big enough to read, the
  /// rest together: on a small phone or with large text, fewer blocks.
  Widget _treemap(BuildContext context, BoxConstraints box, Report report) {
    final names = report.names;
    final ledger = widget.ledger;
    final spending = report.spending;
    final expense = report.expense;
    final scale = textGrowth(context);
    final width = box.maxWidth;
    // What a block needs: its name with the share over its amount.
    final minWidth = 84 * scale;
    final minHeight = 56 * scale;
    final base = width * 0.82;
    var height = base;
    var blocks = _blocksOf(report, names.length);
    var rects = <Rect>[];
    // Taller first, then fewer blocks: a category merged into 其他
    // only when no height up to half again more makes room for it.
    search:
    for (var count = min(7, names.length); count >= 1; count--) {
      blocks = _blocksOf(report, count);
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
                child: CategoryBlock(
                  ledger: ledger,
                  category: name == '其他' && !spending.containsKey('其他')
                      ? _restBlock()
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
  }

  /// The period's entries spent under [name], in a sheet; each opens.
  Future<void> _showCategory(String name) {
    final ledger = widget.ledger;
    final (entries, total) = Report.spentUnder(name, ledger.entries, _period);
    return showSheet<void>(
      context,
      (context) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(Space.s4, 0, Space.s4, Space.s4),
          children: [
            Text(
              name,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: TextSize.heading,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              '${_period.title} · ${entries.length} 筆 · ${ledger.money(total)}',
              textAlign: TextAlign.center,
              style: mutedSmall,
            ),
            const SizedBox(height: Space.s3),
            GroupBox(
              // None: a row's 編輯 and 刪除 reach the card's edges.
              padding: EdgeInsets.zero,
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
}
