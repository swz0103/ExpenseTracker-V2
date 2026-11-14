import 'package:flutter/material.dart';

import 'controls.dart';
import 'figures.dart';
import 'glyphs.dart';
import 'haptics.dart';
import 'headers.dart';
import 'kit.dart';
import 'theme.dart';

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
  Color color = Hue.accent,
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
DateTime _day(DateTime d) => d.isUtc
    ? DateTime.utc(d.year, d.month, d.day)
    : DateTime(d.year, d.month, d.day);

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
    final weekStart = today.subtract(Duration(days: today.weekday - 1));
    final lastMonth = _make(today.year, today.month - 1, 1);
    return [
      ('今天', today, today),
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

  String _label(DateTime d) => d.year == widget.last.year
      ? '${d.month}/${d.day}'
      : '${d.year}/${d.month}/${d.day}';

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
    // The Monday on or before the first of the month.
    final grid = month.subtract(Duration(days: month.weekday - 1));
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
          const SizedBox(height: 12),
          StepSwitch(
            label: '${month.year} 年 ${month.month} 月',
            previousLabel: '上個月',
            nextLabel: '下個月',
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
          const SizedBox(height: 4),
          Row(
            children: [
              for (final name in weekdayNames)
                Expanded(
                  child: Text(
                    name,
                    textAlign: TextAlign.center,
                    style: mutedSmall,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          for (var week = 0; week < 6; week++)
            Row(
              children: [
                for (var d = 0; d < 7; d++)
                  Expanded(
                    child: _cell(
                      _make(grid.year, grid.month, grid.day + week * 7 + d),
                      month,
                    ),
                  ),
              ],
            ),
        ],
      ),
      actions: [
        PanelButton('取消', onTap: () => Navigator.of(context).pop()),
        PanelButton(
          '確定',
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

  Widget _cell(DateTime day, DateTime month) {
    final inMonth = day.month == month.month;
    if (!inMonth) return const SizedBox(height: 44);
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
      label: '${day.month} 月 ${day.day} 日',
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
                child: Text(
                  '${day.day}',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: edge ? FontWeight.w800 : FontWeight.w500,
                    color: out
                        ? Hue.faint
                        : edge
                        ? chosenInk(color)
                        : Hue.ink,
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
  Color color = Hue.accent,
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

String _two(int n) => n.toString().padLeft(2, '0');

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
          duration: const Duration(milliseconds: 250),
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
    return Semantics(
      label: unit,
      value: _two(value),
      child: SizedBox(
        height: 168,
        child: ListWheelScrollView.useDelegate(
          controller: controller,
          itemExtent: 44,
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
                    _two(i),
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: i == value ? Hue.ink : Hue.faint,
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
      detail: '${_two(_hour)}:${_two(_minute)}',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final t in widget.usual)
                ChoicePill(
                  label: '${_two(t.hour)}:${_two(t.minute)}',
                  selected: t.hour == _hour && t.minute == _minute,
                  onTap: () => _set(t),
                ),
            ],
          ),
          const SizedBox(height: 12),
          DecoratedBox(
            decoration: BoxDecoration(
              color: Hue.white,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // The band the chosen hour and minute stop in.
                IgnorePointer(
                  child: Container(
                    height: 44,
                    margin: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: tintOf(color, 0.18),
                      borderRadius: BorderRadius.circular(12),
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
                        fontSize: 26,
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
          ),
        ],
      ),
      actions: [
        PanelButton('取消', onTap: () => Navigator.of(context).pop()),
        PanelButton(
          '確定',
          color: color,
          onTap: () =>
              Navigator.of(context)
                  .pop(TimeOfDay(hour: _hour, minute: _minute)),
        ),
      ],
    );
  }
}
