part of 'recurring_editor.dart';

class _RepeatSheetState extends State<_RepeatSheet> {
  RecurringForm get _f => widget.form;

  Widget _cell(String label, bool chosen, VoidCallback onTap) => Semantics(
    button: true,
    selected: chosen,
    child: Material(
      color: chosen ? AppColors.accent : AppColors.surface,
      borderRadius: BorderRadius.circular(Radii.medium),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.medium),
        onTap: () => setState(onTap),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: TextSize.body,
                fontWeight: FontWeight.w800,
                color: chosen ? AppColors.onAccent : AppColors.ink,
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _days() => CardGrid(columns: 7, gap: 6, [
    for (var d = 1; d <= 31; d++)
      _cell('$d', _f.day == d, () => _f.setDayOfMonth(d)),
  ]);

  /// The days of the week, from Sunday, to choose which a weekly item
  /// falls on.
  Widget _weekdays() => Row(
    children: [
      for (final (i, name) in weekdayNames.indexed) ...[
        if (i > 0) const SizedBox(width: Space.s2),
        Expanded(
          child: _cell(
            name,
            weekdayIndex(_f.start) == i,
            () => _f.setWeekday(weekdayAt(i)),
          ),
        ),
      ],
    ],
  );

  /// 哪個月 and 哪一天: the month and the day a yearly item falls on.
  Widget _dayOfYear() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text('哪個月', style: mutedSmall),
      const SizedBox(height: Space.s2),
      CardGrid(columns: 6, gap: 6, [
        for (var m = 1; m <= 12; m++)
          _cell('$m', _f.start.month == m, () => _setMonth(m)),
      ]),
      const SizedBox(height: Space.s3),
      const Text('哪一天', style: mutedSmall),
      const SizedBox(height: Space.s2),
      CardGrid(columns: 7, gap: 6, [
        for (var d = 1; d <= 31; d++)
          _cell('$d', _f.start.day == d, () {
            final s = _f.start;
            final day = DateTime.utc(s.year, s.month, d);
            if (day.month == s.month) _f.start = day;
          }),
      ]),
    ],
  );

  /// 每 n 天, 週, 月 or 年, with − and + to change n.
  Widget _every() => Row(
    children: [
      const Text('每', style: TextStyle(fontSize: TextSize.title)),
      IconButton(
        tooltip: '少一',
        onPressed: _f.every > 1 ? () => setState(() => _f.step(-1)) : null,
        icon: const Text(
          '−',
          style: TextStyle(
            fontSize: TextSize.large,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      Text(
        '${_f.every}',
        style: const TextStyle(
          fontSize: TextSize.heading,
          fontWeight: FontWeight.w800,
        ),
      ),
      IconButton(
        tooltip: '多一',
        onPressed: () => setState(() => _f.step(1)),
        icon: const GlyphIcon(Glyph.add, size: 20),
      ),
      Text(
        repeatUnitLabel(_f.unit),
        style: const TextStyle(fontSize: TextSize.title),
      ),
    ],
  );

  void _setMonth(int month) {
    final start = _f.start;
    var day = DateTime.utc(start.year, month, start.day);
    if (day.month != month) day = monthEnd(start.year, month);
    if (day.isBefore(dayOf(start))) {
      day = monthsAfter(day, 12);
    }
    _f.start = day;
  }

  @override
  Widget build(BuildContext context) {
    const units = [
      (RepeatUnit.day, '每天'),
      (RepeatUnit.week, '每週'),
      (RepeatUnit.month, '每月'),
      (RepeatUnit.year, '每年'),
    ];
    final next = nextTimes(_f.build(), _f.start);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Space.s4, 0, Space.s4, Space.s4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(
            child: Text(
              '多久一次',
              style: TextStyle(
                fontSize: TextSize.heading,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: Space.s3),
          Row(
            children: [
              for (final (i, (unit, label)) in units.indexed) ...[
                if (i > 0) const SizedBox(width: Space.s2),
                Expanded(
                  child: _cell(label, _f.unit == unit, () => _f.unit = unit),
                ),
              ],
            ],
          ),
          const SizedBox(height: Space.s4),
          switch (_f.unit) {
            RepeatUnit.month => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('每個月的哪一天', style: mutedSmall),
                const SizedBox(height: Space.s2),
                _days(),
              ],
            ),
            RepeatUnit.week => _weekdays(),
            RepeatUnit.year => _dayOfYear(),
            RepeatUnit.day => const SizedBox(),
          },
          const SizedBox(height: Space.s4),
          _every(),
          const SizedBox(height: Space.s2),
          Text(
            '接下來：${next.map((d) => formatMd(d)).join('、')}',
            textAlign: TextAlign.center,
            style: mutedSmall,
          ),
          const SizedBox(height: Space.s3),
          PanelButton(
            Words.done,
            color: AppColors.accent,
            onTap: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

/// 其他設定: when it starts and ends, whether it books itself when due,
/// and whether it is paused.
class _OtherSheet extends StatefulWidget {
  const _OtherSheet({required this.form, required this.today});

  final RecurringForm form;

  /// The ledger's today: an end can be set up to five years after it.
  final DateTime today;

  @override
  State<_OtherSheet> createState() => _OtherSheetState();
}

class _OtherSheetState extends State<_OtherSheet> {
  RecurringForm get _f => widget.form;

  Future<DateTime?> _pick(String title, DateTime selected) => pickDate(
    context,
    title: title,
    selected: selected,
    latest: DateTime.utc(widget.today.year + 5),
  );

  Widget _date(
    String label,
    String value,
    VoidCallback onTap, {
    VoidCallback? onClear,
  }) => ColorCard(
    controlsInside: true,
    color: AppColors.faint,
    amount: 0.18,
    radius: Radii.large,
    onTap: onTap,
    label: '$label $value',
    padding: const EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s1, Space.s2),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: mutedSmall),
              Text(
                value,
                style: const TextStyle(
                  fontSize: TextSize.heading,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        if (onClear != null)
          IconButton(
            tooltip: '不結束',
            onPressed: onClear,
            icon: const GlyphIcon(
              Glyph.close,
              size: 16,
              color: AppColors.muted,
            ),
          ),
      ],
    ),
  );

  Widget _toggle(
    String title,
    String detail,
    bool value,
    ValueChanged<bool> set,
  ) => ColorCard(
    controlsInside: true,
    color: AppColors.faint,
    amount: 0.18,
    radius: Radii.large,
    onTap: () => setState(() => set(!value)),
    padding: const EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s2, Space.s2),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: TextSize.body,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(detail, style: mutedSmall),
            ],
          ),
        ),
        TickSwitch(
          value: value,
          label: title,
          onChanged: (v) => setState(() => set(v)),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final start = _f.start;
    final end = _f.end;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.s4, 0, Space.s4, Space.s4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(
            child: Text(
              '其他設定',
              style: TextStyle(
                fontSize: TextSize.heading,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: Space.s3),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _date('開始', formatMd(start), () async {
                    final day = await _pick('開始日', start);
                    if (day != null) setState(() => _f.start = day);
                  }),
                ),
                const SizedBox(width: Space.s2),
                Expanded(
                  child: _date(
                    '結束',
                    end == null ? '不結束' : formatMd(end),
                    () async {
                      final day = await _pick('結束日', end ?? start);
                      if (day != null) setState(() => _f.end = day);
                    },
                    onClear: end == null
                        ? null
                        : () => setState(() => _f.end = null),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Space.s2),
          // One to a row: side by side, their words broke onto a second
          // line on every phone.
          _toggle('到期自動入帳', '到期就自動記一筆', _f.auto, (v) => _f.auto = v),
          const SizedBox(height: Space.s2),
          _toggle('暫停', '先不出現在月曆', !_f.active, (v) => _f.active = !v),
          const SizedBox(height: Space.s4),
          PanelButton(
            Words.done,
            color: AppColors.accent,
            onTap: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}
