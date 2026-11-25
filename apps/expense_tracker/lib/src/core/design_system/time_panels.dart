import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'controls.dart';
import 'glyphs.dart';
import 'haptics.dart';
import 'page_header.dart';
import 'components.dart';
import 'theme.dart';
import '../../../design_system/display/date.dart';
import 'shape.dart';
import 'spacing.dart';
import 'month_grid.dart';
import 'motion.dart';
import '../formatting/words.dart';

import 'package:core/time/utc_days.dart';

// The app's own date range and time pickers, as panels in the middle of
// the screen: quick choices on top, then a month to tap the days on, or
// two wheels for the hour and the minute.

/// Opens a panel to choose a run of days from [first] to [last]: 今天,
/// 本週, 本月, 上月 and 今年 on top, then a month where the first tap
/// sets the start and the second the end. Null when left without 確定.
Future<DateTimeRange?> pickDateRange(
  BuildContext context, {
  required DateTime first,
  required DateTime last,
  DateTimeRange? initial,
  String title = '選擇日期',
  Color color = AppColors.accent,
}) {
  return showPanel<DateTimeRange>(
    context,
    (context) => _RangePanel(
      first: _day(first),
      last: _day(last),
      initial: initial,
      title: title,
      color: color,
    ),
  );
}

/// [d] at the start of its day, kept in UTC or local as it came.
DateTime _day(DateTime d) =>
    d.isUtc ? dayOf(d) : DateTime(d.year, d.month, d.day);

class _RangePanel extends StatefulWidget {
  const _RangePanel({
    required this.first,
    required this.last,
    required this.initial,
    required this.title,
    required this.color,
  });

  final DateTime first;
  final DateTime last;
  final DateTimeRange? initial;
  final String title;
  final Color color;

  @override
  State<_RangePanel> createState() => _RangePanelState();
}

class _RangePanelState extends State<_RangePanel> {
  late DateTime? _start = switch (widget.initial) {
    final r? => _day(r.start),
    null => null,
  };
  late DateTime? _end = switch (widget.initial) {
    final r? => _day(r.end),
    null => null,
  };
  late DateTime _month = _monthOf(_end ?? widget.last);

  DateTime _make(int y, int m, int d) =>
      widget.last.isUtc ? DateTime.utc(y, m, d) : DateTime(y, m, d);

  DateTime _monthOf(DateTime d) => _make(d.year, d.month, 1);

  DateTime _clamp(DateTime d) => d.isBefore(widget.first)
      ? widget.first
      : d.isAfter(widget.last)
      ? widget.last
      : d;

  /// The quick choices, each as the days it covers within the limits.
  List<(String, DateTime, DateTime)> get _quick {
    final today = widget.last;
    final weekStart = startOfWeek(today);
    final lastMonth = _make(today.year, today.month - 1, 1);
    return [
      (Words.today, today, today),
      ('本週', weekStart, today),
      ('本月', _make(today.year, today.month, 1), today),
      ('上月', lastMonth, _make(today.year, today.month, 0)),
      ('今年', _make(today.year, 1, 1), today),
    ];
  }

  void _tap(DateTime day) {
    Haptics.selection();
    setState(() {
      final start = _start;
      if (start == null || _end != null || day.isBefore(start)) {
        _start = day;
        _end = null;
      } else {
        _end = day;
      }
    });
  }

  void _quickPick(DateTime from, DateTime to) {
    Haptics.selection();
    setState(() {
      _start = _clamp(from);
      _end = _clamp(to);
      _month = _monthOf(_end!);
    });
  }

  String _label(DateTime d) =>
      d.year == widget.last.year ? formatMd(d) : formatYMd(d);

  @override
  Widget build(BuildContext context) {
    final start = _start;
    final end = _end;
    final color = widget.color;
    final detail = start == null
        ? '點開始那天，再點結束那天'
        : end == null
        ? '${_label(start)} 起，再點結束那天'
        : start == end
        ? _label(start)
        : '${_label(start)} – ${_label(end)}';
    final month = _month;
    final atStart = !month.isAfter(_monthOf(widget.first));
    final atEnd = !month.isBefore(_monthOf(widget.last));
    return CenterPanel(
      glyph: Glyph.calendar,
      color: color,
      title: widget.title,
      detail: detail,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final (label, from, to) in _quick)
                if (!to.isBefore(widget.first))
                  ChoicePill(
                    label: label,
                    selected: start == _clamp(from) && end == _clamp(to),
                    onTap: () => _quickPick(from, to),
                  ),
            ],
          ),
          const SizedBox(height: Space.s3),
          StepSwitch(
            label: formatYMMM(month),
            previousLabel: Words.previousMonth,
            nextLabel: Words.nextMonth,
            iconSize: 20,
            expand: true,
            onPrevious: atStart
                ? null
                : () => setState(
                    () => _month = _make(month.year, month.month - 1, 1),
                  ),
            onNext: atEnd
                ? null
                : () => setState(
                    () => _month = _make(month.year, month.month + 1, 1),
                  ),
          ),
          const SizedBox(height: Space.s1),
          MonthGrid(
            year: month.year,
            month: month.month,
            blank: 44,
            day: (d) => _cell(_make(month.year, month.month, d)),
          ),
        ],
      ),
      actions: [
        PanelButton(Words.cancel, onTap: () => Navigator.of(context).pop()),
        PanelButton(
          Words.done,
          color: color,
          onTap: start == null
              ? null
              : () =>
                    Navigator.of(context)
                        .pop(DateTimeRange(start: start, end: end ?? start)),
        ),
      ],
    );
  }

  Widget _cell(DateTime day) {
    final start = _start;
    final end = _end ?? start;
    final out = day.isBefore(widget.first) || day.isAfter(widget.last);
    final edge = day == start || day == end;
    final inside =
        start != null &&
        end != null &&
        !day.isBefore(start) &&
        !day.isAfter(end);
    final color = widget.color;
    final band = inside && start != end;
    return Semantics(
      button: !out,
      selected: inside,
      label: formatMMMd(day),
      onTap: out ? null : () => _tap(day),
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: out ? null : () => _tap(day),
        child: SizedBox(
          height: 44,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (band)
                Positioned.fill(
                  top: 4,
                  bottom: 4,
                  left: day == start ? 22 : 0,
                  right: day == end ? 22 : 0,
                  child: ColoredBox(color: tintOf(color, 0.22)),
                ),
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: edge ? chosenFill(color) : null,
                  shape: BoxShape.circle,
                  border: edge && Shade.dark
                      ? Border.all(color: color, width: 1.5)
                      : null,
                ),
                // Grows with the phone's text until the circle is full, then
                // keeps to it, as the seven days must share the width.
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '${day.day}',
                    style: TextStyle(
                      fontSize: TextSize.body,
                      fontWeight: edge ? FontWeight.w800 : FontWeight.w500,
                      color: out
                          ? AppColors.faint
                          : edge
                          ? chosenInk(color)
                          : AppColors.ink,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Opens a panel to choose a time of day: the usual times on top, then
/// a wheel for the hour and one for the minute. Null when left without
/// 確定.
Future<TimeOfDay?> pickTime(
  BuildContext context, {
  required TimeOfDay initial,
  String title = '選擇時間',
  Color color = AppColors.accent,
  List<TimeOfDay> usual = const [
    TimeOfDay(hour: 8, minute: 0),
    TimeOfDay(hour: 12, minute: 0),
    TimeOfDay(hour: 18, minute: 0),
    TimeOfDay(hour: 21, minute: 0),
    TimeOfDay(hour: 22, minute: 30),
  ],
}) {
  return showPanel<TimeOfDay>(
    context,
    (context) =>
        _TimePanel(initial: initial, title: title, color: color, usual: usual),
  );
}

class _TimePanel extends StatefulWidget {
  const _TimePanel({
    required this.initial,
    required this.title,
    required this.color,
    required this.usual,
  });

  final TimeOfDay initial;
  final String title;
  final Color color;
  final List<TimeOfDay> usual;

  @override
  State<_TimePanel> createState() => _TimePanelState();
}

class _TimePanelState extends State<_TimePanel> {
  late var _hour = widget.initial.hour;
  late var _minute = widget.initial.minute;
  late final _hours = FixedExtentScrollController(initialItem: _hour);
  late final _minutes = FixedExtentScrollController(initialItem: _minute);

  @override
  void dispose() {
    _hours.dispose();
    _minutes.dispose();
    super.dispose();
  }

  void _set(TimeOfDay t) {
    Haptics.selection();
    setState(() {
      _hour = t.hour;
      _minute = t.minute;
    });
    final quiet = MediaQuery.disableAnimationsOf(context);
    for (final (wheel, item) in [(_hours, t.hour), (_minutes, t.minute)]) {
      if (quiet) {
        wheel.jumpToItem(item);
      } else {
        wheel.animateToItem(
          item,
          // Exception to motion: jumped to instead while motion is off.
          duration: Motion.medium1,
          curve: Curves.easeOutCubic,
        );
      }
    }
  }

  Widget _wheel(
    FixedExtentScrollController controller,
    int count,
    String unit,
    ValueChanged<int> onChanged,
    int value,
  ) {
    // Each line as tall as its figure at the phone's text size (one and a
    // half times the letters), 44 at least: a fixed 44 cut the figures off
    // once the text was larger.
    final extent = math.max(44.0, TextSize.figure * textGrowth(context) * 1.5);
    return Semantics(
      label: unit,
      value: formatTimeField(value),
      child: SizedBox(
        height: extent * 168 / 44,
        child: ListWheelScrollView.useDelegate(
          controller: controller,
          itemExtent: extent,
          diameterRatio: 4,
          physics: const FixedExtentScrollPhysics(),
          onSelectedItemChanged: (i) {
            Haptics.selection();
            onChanged(i % count);
          },
          childDelegate: ListWheelChildLoopingListDelegate(
            children: [
              for (var i = 0; i < count; i++)
                Center(
                  child: Text(
                    formatTimeField(i),
                    style: TextStyle(
                      fontSize: TextSize.figure,
                      fontWeight: FontWeight.w800,
                      color: i == value ? AppColors.ink : AppColors.faint,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color;
    return CenterPanel(
      glyph: Glyph.bell,
      color: color,
      title: widget.title,
      detail: formatHm(_hour, _minute),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _usual(),
          const SizedBox(height: Space.s3),
          _wheels(color),
        ],
      ),
      actions: [
        PanelButton(Words.cancel, onTap: () => Navigator.of(context).pop()),
        PanelButton(
          Words.done,
          color: color,
          onTap: () =>
              Navigator.of(context)
                  .pop(TimeOfDay(hour: _hour, minute: _minute)),
        ),
      ],
    );
  }

  /// The usual times as pills, the one chosen marked.
  Widget _usual() => Wrap(
    spacing: 6,
    runSpacing: 6,
    children: [
      for (final t in widget.usual)
        ChoicePill(
          label: formatHm(t.hour, t.minute),
          selected: t.hour == _hour && t.minute == _minute,
          onTap: () => _set(t),
        ),
    ],
  );

  /// The hour and minute wheels on white, over a band in [color] where
  /// the chosen ones stop.
  Widget _wheels(Color color) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(Radii.large),
    ),
    child: Stack(
      alignment: Alignment.center,
      children: [
        // The band the chosen hour and minute stop in.
        IgnorePointer(
          child: Container(
            height: 44,
            margin: const EdgeInsets.symmetric(horizontal: Space.s2),
            decoration: BoxDecoration(
              color: tintOf(color, 0.18),
              borderRadius: BorderRadius.circular(Radii.medium),
            ),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: _wheel(
                _hours,
                24,
                '時',
                (h) => setState(() => _hour = h),
                _hour,
              ),
            ),
            const Text(
              ':',
              style: TextStyle(
                fontSize: TextSize.figure,
                fontWeight: FontWeight.w800,
              ),
            ),
            Expanded(
              child: _wheel(
                _minutes,
                60,
                '分',
                (m) => setState(() => _minute = m),
                _minute,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}
