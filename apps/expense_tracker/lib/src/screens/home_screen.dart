import 'dart:math';

import 'package:flutter/material.dart';

import '../book.dart';
import '../charts/chart_data.dart';
import '../charts/chart_parts.dart';
import '../theme.dart';
import '../ui/kit.dart';
import '../ui/mini_charts.dart';

/// The first screen: this month against income and budget, what is still
/// to record, one chart that switches between days, categories and
/// investments, and below it the entries the chart points at. Everything
/// is read off the page itself; only the entries scroll.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.book});

  final Book book;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

enum _View { days, pace, categories, months, weekdays, holdings, worth }

class _HomeScreenState extends State<HomeScreen> {
  var _view = _View.days;
  late int _day = widget.book.today.day;
  String? _category;
  int? _holding;
  int? _month;
  int? _weekday;
  int? _worth;

  /// Below this height the entries would be squeezed out, so the whole
  /// page scrolls instead.
  static const _compact = 600.0;

  DateTime get _date {
    final today = widget.book.today;
    return DateTime.utc(today.year, today.month, _day);
  }

  @override
  Widget build(BuildContext context) {
    final book = widget.book;
    return ListenableBuilder(
      listenable: book,
      builder: (context, _) => LayoutBuilder(
        builder: (context, constraints) {
          final top = [
            ScreenHeader(
              title: '${book.today.month} 月',
              onTitleTap: () => comingSoon(context, '切換月份'),
              actions: [
                IconButton(
                  tooltip: '提醒',
                  onPressed: () => comingSoon(context, '提醒'),
                  icon: const Icon(Icons.notifications_none),
                ),
              ],
            ),
            _MonthSummary(book),
            const SizedBox(height: 12),
            _BudgetLine(book),
            if (book.reminders.isNotEmpty) ...[
              const SizedBox(height: 12),
              _Reminders(book.reminders),
            ],
            const SizedBox(height: 14),
            _chart(context),
          ];
          final (heading, entries) = _list(context);
          const padding = EdgeInsets.symmetric(horizontal: 16);
          if (constraints.maxHeight < _compact) {
            return ListView(
              padding: padding,
              children: [...top, heading, ...entries],
            );
          }
          return Padding(
            padding: padding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...top,
                heading,
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: 12),
                    children: entries,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// The switchable chart with a line of figures over it.
  Widget _chart(BuildContext context) {
    final book = widget.book;
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(color: Palette.muted);
    final strong = text.bodySmall?.copyWith(
      color: Palette.ink,
      fontWeight: FontWeight.w600,
    );
    final InlineSpan info;
    final Widget chart;
    switch (_view) {
      case _View.days:
        final days = book.monthDays;
        final spent = days.fold(0, (a, b) => a + b);
        final average = days.isEmpty ? 0 : spent ~/ days.length;
        final highest = days.isEmpty ? 0 : days.reduce(max);
        final peak = days.indexOf(highest) + 1;
        info = TextSpan(
          children: [
            const TextSpan(text: '日均 '),
            TextSpan(text: groupDigits(average), style: strong),
            TextSpan(text: '　最高 ${book.today.month}/$peak '),
            TextSpan(text: groupDigits(highest), style: strong),
          ],
        );
        chart = DailyBars(
          days: days,
          length: book.daysInMonth,
          month: book.today.month,
          selected: _day,
          onSelect: (day) => setState(() => _day = day),
        );
      case _View.categories:
        final rows = book.monthCategories;
        final total = rows.fold(0, (sum, row) => sum + row.$2);
        final picked = rows.indexWhere((row) => row.$1 == _category);
        info = picked < 0
            ? TextSpan(
                children: [
                  TextSpan(text: '本月 ${rows.length} 類　共 '),
                  TextSpan(text: groupDigits(total), style: strong),
                  const TextSpan(text: '　點一類看明細'),
                ],
              )
            : TextSpan(
                children: [
                  TextSpan(text: '${rows[picked].$1} ', style: strong),
                  TextSpan(text: groupDigits(rows[picked].$2), style: strong),
                  TextSpan(
                    text: '　占 ${(rows[picked].$2 * 100 / total).round()}%',
                  ),
                ],
              );
        chart = BarRows(
          rows: [
            for (final (name, amount) in rows.take(6))
              BarRow(
                name,
                amount,
                '${(amount * 100 / max(1, total)).round()}%',
              ),
          ],
          selected: picked < 0 ? null : picked,
          onSelect: (index) => setState(() {
            final name = rows[index].$1;
            _category = name == _category ? null : name;
          }),
        );
      case _View.pace:
        final days = book.monthDays;
        final length = book.daysInMonth;
        final month = book.today.month;
        final totals = <int>[];
        var running = 0;
        for (final amount in days) {
          running += amount;
          totals.add(running);
        }
        final last = max(1, totals.length);
        final day = _day.clamp(1, last);
        final even = [
          for (var d = 1; d <= length; d++) book.budget * d ~/ length,
        ];
        final at = totals.isEmpty ? 0 : totals[day - 1];
        final ahead = at - even[day - 1];
        final gap = groupDigits(ahead.abs());
        info = TextSpan(
          children: [
            TextSpan(text: '$month/$day 累計 '),
            TextSpan(text: groupDigits(at), style: strong),
            TextSpan(
              text: ahead > 0 ? '　比預算線多 $gap' : '　比預算線少 $gap',
              style: TextStyle(color: ahead > 0 ? Palette.warn : Palette.clay),
            ),
          ],
        );
        chart = LineChart(
          values: totals,
          slots: length,
          reference: even,
          fromZero: true,
          selected: day - 1,
          labels: {0: '$month/1', length - 1: '$month/$length'},
          onSelect: (index) => setState(() => _day = index + 1),
        );
      case _View.months:
        final history = book.history;
        final recent = history.sublist(max(0, history.length - 6));
        final last = recent.length - 1;
        final picked = (_month ?? last).clamp(0, last);
        final shown = recent[picked];
        info = TextSpan(
          children: [
            TextSpan(text: '${shown.month}月　收入 '),
            TextSpan(text: groupDigits(shown.income), style: strong),
            const TextSpan(text: '　支出 '),
            TextSpan(text: groupDigits(shown.expense), style: strong),
            TextSpan(
              text: '　結餘 ${signed(shown.net)}',
              style: TextStyle(
                color: shown.net < 0 ? Palette.warn : Palette.clay,
              ),
            ),
          ],
        );
        chart = ColumnChart(
          series: [
            [for (final m in recent) m.income],
            [for (final m in recent) m.expense],
          ],
          colors: const [Palette.clay, Palette.peach],
          labels: [for (final m in recent) m.label],
          selected: picked,
          onSelect: (index) => setState(() => _month = index),
        );
      case _View.weekdays:
        final averages = book.weekdayAverages;
        final picked = _weekday;
        final weekend = (averages[5] + averages[6]) ~/ 2;
        final weekday = averages.take(5).fold(0, (a, b) => a + b) ~/ 5;
        info = picked == null
            ? TextSpan(
                children: [
                  const TextSpan(text: '平日平均 '),
                  TextSpan(text: groupDigits(weekday), style: strong),
                  const TextSpan(text: '　週末平均 '),
                  TextSpan(text: groupDigits(weekend), style: strong),
                ],
              )
            : TextSpan(
                children: [
                  TextSpan(text: '週${weekdayNames[picked]}平均 '),
                  TextSpan(text: groupDigits(averages[picked]), style: strong),
                  const TextSpan(text: '　近兩個月'),
                ],
              );
        chart = ColumnChart(
          series: [averages],
          colors: const [Palette.clay],
          labels: weekdayNames,
          selected: picked,
          onSelect: (index) => setState(() {
            _weekday = index == _weekday ? null : index;
          }),
        );
      case _View.worth:
        final values = book.investHistory;
        final last = values.length - 1;
        final picked = (_worth ?? last).clamp(0, last);
        final date = book.today.subtract(Duration(days: last - picked));
        final change = values[picked] - values.first;
        info = TextSpan(
          children: [
            TextSpan(text: '${date.month}/${date.day} 市值 '),
            TextSpan(text: groupDigits(values[picked]), style: strong),
            const TextSpan(text: '　比起點 '),
            TextSpan(
              text: signed(change),
              style: TextStyle(color: gainColor(change)),
            ),
          ],
        );
        chart = LineChart(
          values: values,
          selected: picked,
          labels: {0: '${values.length} 天前', last: '今天'},
          onSelect: (index) => setState(() => _worth = index),
        );
      case _View.holdings:
        final holdings = book.holdings;
        final value = book.investValue;
        final picked = _holding;
        if (picked == null) {
          final cost = holdings.fold(0, (sum, h) => sum + h.cost);
          final change = holdings.fold(0, (sum, h) => sum + h.change);
          info = TextSpan(
            children: [
              const TextSpan(text: '市值 '),
              TextSpan(text: groupDigits(value), style: strong),
              TextSpan(
                text: '　${percent(value - cost, cost)}',
                style: TextStyle(color: gainColor(value - cost)),
              ),
              const TextSpan(text: '　今日 '),
              TextSpan(
                text: signed(change),
                style: TextStyle(color: gainColor(change)),
              ),
            ],
          );
        } else {
          final h = holdings[picked];
          info = TextSpan(
            children: [
              TextSpan(text: '${h.name} ${h.code}　', style: strong),
              TextSpan(text: '成本 ${groupDigits(h.cost)}　'),
              TextSpan(
                text: '損益 ${signed(h.gain)}',
                style: TextStyle(color: gainColor(h.gain)),
              ),
              const TextSpan(text: '　今日 '),
              TextSpan(
                text: signed(h.change),
                style: TextStyle(color: gainColor(h.change)),
              ),
            ],
          );
        }
        chart = BarRows(
          rows: [
            for (final h in holdings)
              BarRow(
                h.name,
                h.value,
                percent(h.gain, h.cost),
                noteColor: gainColor(h.gain),
              ),
          ],
          selected: picked,
          onSelect: (index) => setState(() {
            _holding = index == _holding ? null : index;
          }),
        );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final (view, label) in const [
                (_View.days, '每日'),
                (_View.pace, '累計'),
                (_View.categories, '分類'),
                (_View.months, '收支'),
                (_View.weekdays, '週間'),
                (_View.holdings, '投資'),
                (_View.worth, '市值'),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _Chip(
                    label,
                    selected: view == _view,
                    onTap: () => setState(() => _view = view),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text.rich(TextSpan(style: muted, children: [info])),
        ),
        const SizedBox(height: 6),
        SizedBox(height: 120, child: chart),
      ],
    );
  }

  /// The heading and rows under the chart: the chosen category's entries
  /// this month, or the chosen day's.
  (Widget, List<Widget>) _list(BuildContext context) {
    final book = widget.book;
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(color: Palette.muted);
    final category = _view == _View.categories ? _category : null;
    final String title;
    final int spent;
    final List<Widget> rows;
    if (category != null) {
      final found = book.monthEntriesIn(category);
      title = '$category・本月';
      spent = found.fold(0, (sum, item) => sum + item.$2.amount);
      rows = [for (final (date, entry) in found) EntryRow(entry, date: date)];
    } else {
      final date = _date;
      title = date == book.today ? '今天' : shortDay(date);
      spent = book.total(date, EntryKind.expense);
      rows = [for (final entry in book.on(date)) EntryRow(entry)];
    }
    final heading = Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 2),
      child: Row(
        children: [
          Text(title, style: text.titleSmall),
          const Spacer(),
          Text('支出 ${groupDigits(spent)}', style: muted),
        ],
      ),
    );
    if (rows.isEmpty) {
      rows.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Text('沒有記帳', style: muted),
        ),
      );
    }
    return (heading, rows);
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.label, {required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? Palette.clay : Palette.wash,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium
              ?.copyWith(color: selected ? Palette.card : Palette.ink),
        ),
      ),
    );
  }
}

/// Spending in large type, with income and what is left beside it.
class _MonthSummary extends StatelessWidget {
  const _MonthSummary(this.book);

  final Book book;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(color: Palette.muted);
    final expense = book.monthTotal(EntryKind.expense);
    final income = book.monthTotal(EntryKind.income);
    final left = income - expense;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('本月支出', style: muted),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  dollars(expense),
                  style: text.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text.rich(
              TextSpan(
                style: muted,
                children: [
                  const TextSpan(text: '收入 '),
                  TextSpan(
                    text: groupDigits(income),
                    style: text.bodyMedium?.copyWith(
                      color: Palette.clay,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Text.rich(
              TextSpan(
                style: muted,
                children: [
                  const TextSpan(text: '結餘 '),
                  TextSpan(
                    text: signed(left),
                    style: text.bodyMedium?.copyWith(
                      color: left < 0 ? Palette.warn : Palette.ink,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Spending against the budget, with a tick for how much of the month
/// has gone; tap to read what each day may still take.
class _BudgetLine extends StatefulWidget {
  const _BudgetLine(this.book);

  final Book book;

  @override
  State<_BudgetLine> createState() => _BudgetLineState();
}

class _BudgetLineState extends State<_BudgetLine> {
  var _perDay = false;

  @override
  Widget build(BuildContext context) {
    final book = widget.book;
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(color: Palette.muted);
    final spent = book.monthTotal(EntryKind.expense);
    final left = book.budget - spent;
    final daysLeft = book.daysInMonth - book.today.day + 1;
    final used = (spent * 100 / book.budget).round();
    final note = _perDay
        ? '每天可花 ${groupDigits(max(0, left) ~/ daysLeft)}'
        : left >= 0
        ? '已用 $used%・剩 ${groupDigits(left)}'
        : '超出 ${groupDigits(-left)}';
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _perDay = !_perDay),
      child: Column(
        children: [
          Row(
            children: [
              Text('預算 ${groupDigits(book.budget)}', style: muted),
              const Spacer(),
              Text(
                note,
                style: muted?.copyWith(
                  color: left < 0 ? Palette.warn : Palette.ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 14,
            width: double.infinity,
            child: CustomPaint(
              painter: _BudgetPainter(
                used: spent / book.budget,
                elapsed: book.today.day / book.daysInMonth,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BudgetPainter extends CustomPainter {
  _BudgetPainter({required this.used, required this.elapsed});

  final double used;
  final double elapsed;

  @override
  void paint(Canvas canvas, Size size) {
    const bar = 8.0;
    final top = (size.height - bar) / 2;
    final track = RRect.fromLTRBR(
      0,
      top,
      size.width,
      top + bar,
      const Radius.circular(bar / 2),
    );
    canvas.drawRRect(track, Paint()..color = Palette.wash);
    final fill = size.width * used.clamp(0.0, 1.0);
    canvas.drawRRect(
      RRect.fromLTRBR(0, top, fill, top + bar, const Radius.circular(bar / 2)),
      Paint()..color = used > 1 ? Palette.warn : Palette.clay,
    );
    final x = size.width * elapsed.clamp(0.0, 1.0);
    canvas.drawRRect(
      RRect.fromLTRBR(x - 1, 0, x + 1, size.height, const Radius.circular(1)),
      Paint()..color = Palette.ink,
    );
  }

  @override
  bool shouldRepaint(_BudgetPainter old) =>
      old.used != used || old.elapsed != elapsed;
}

/// What is still to record, as small tags in one line.
class _Reminders extends StatelessWidget {
  const _Reminders(this.items);

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final item in items)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Palette.wash,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.edit_note, size: 16, color: Palette.clay),
                  const SizedBox(width: 4),
                  Text(item, style: style),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// One row of [BarRows].
final class BarRow {
  const BarRow(this.label, this.value, this.note, {this.noteColor});

  final String label;
  final int value;

  /// Shown at the end of the bar, such as a share or a gain.
  final String note;
  final Color? noteColor;
}

/// Labelled horizontal bars, one per row; tap a row to choose it.
class BarRows extends StatelessWidget {
  const BarRows({
    super.key,
    required this.rows,
    required this.selected,
    required this.onSelect,
  });

  final List<BarRow> rows;
  final int? selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final label = Theme.of(context).textTheme.labelMedium!;
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight / max(rows.length, 5);
        return GestureDetector(
          onTapDown: (details) {
            final index = details.localPosition.dy ~/ height;
            if (index >= 0 && index < rows.length) onSelect(index);
          },
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: 1),
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOutCubic,
            builder: (context, grow, _) => CustomPaint(
              size: Size.infinite,
              painter: _RowsPainter(
                rows: rows,
                rowHeight: height,
                selected: selected,
                grow: grow,
                label: label,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RowsPainter extends CustomPainter {
  _RowsPainter({
    required this.rows,
    required this.rowHeight,
    required this.selected,
    required this.grow,
    required this.label,
  });

  final List<BarRow> rows;
  final double rowHeight;
  final int? selected;
  final double grow;
  final TextStyle label;

  static const _labelWidth = 76.0;
  static const _noteWidth = 56.0;

  @override
  void paint(Canvas canvas, Size size) {
    final largest = rows.fold(1, (m, row) => max(m, row.value));
    final room = size.width - _labelWidth - _noteWidth;
    final bar = min(12.0, rowHeight * 0.5);
    for (final (i, row) in rows.indexed) {
      final middle = rowHeight * (i + 0.5);
      final picked = i == selected;
      final faded = selected != null && !picked;
      final ink = faded ? Palette.muted : Palette.ink;
      paintText(
        canvas,
        row.label,
        label.copyWith(
          color: ink,
          fontWeight: picked ? FontWeight.w700 : FontWeight.w400,
        ),
        Offset(0, middle),
        anchor: const Offset(0, 0.5),
        maxWidth: _labelWidth - 6,
      );
      final length = max(3.0, room * row.value / largest * grow);
      canvas.drawRRect(
        RRect.fromLTRBR(
          _labelWidth,
          middle - bar / 2,
          _labelWidth + length,
          middle + bar / 2,
          Radius.circular(bar / 2),
        ),
        Paint()
          ..color = picked || selected == null && i == 0
              ? Palette.clay
              : Palette.peach,
      );
      paintText(
        canvas,
        picked ? groupDigits(row.value) : row.note,
        label.copyWith(
          color: picked ? Palette.ink : row.noteColor ?? ink,
          fontWeight: picked ? FontWeight.w700 : FontWeight.w400,
        ),
        Offset(_labelWidth + length + 6, middle),
        anchor: const Offset(0, 0.5),
      );
    }
  }

  @override
  bool shouldRepaint(_RowsPainter old) =>
      old.selected != selected || old.grow != grow || old.rows != rows;
}

/// A bar for each day of the month. Tap or drag across them to choose a
/// day; the chosen one is drawn in the accent with its amount on top.
class DailyBars extends StatelessWidget {
  const DailyBars({
    super.key,
    required this.days,
    required this.length,
    required this.month,
    required this.selected,
    required this.onSelect,
  });

  /// Spending on each day so far, the 1st first.
  final List<int> days;

  /// Days in the month.
  final int length;
  final int month;
  final int selected;
  final ValueChanged<int> onSelect;

  void _pick(Offset at, double width) {
    final day = (at.dx / width * length).floor() + 1;
    final last = max(1, days.length);
    final known = day.clamp(1, last);
    if (known != selected) onSelect(known);
  }

  @override
  Widget build(BuildContext context) {
    final label = Theme.of(context).textTheme.labelSmall!;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return GestureDetector(
          onTapDown: (d) => _pick(d.localPosition, width),
          onHorizontalDragUpdate: (d) => _pick(d.localPosition, width),
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: 1),
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutCubic,
            builder: (context, grow, _) => CustomPaint(
              size: Size.infinite,
              painter: _BarsPainter(
                days: days,
                length: length,
                month: month,
                selected: selected,
                grow: grow,
                label: label,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// `1200` → `+1,200`.
String signed(int value) =>
    value > 0 ? '+${groupDigits(value)}' : groupDigits(value);

/// [part] of [whole] with a sign and one decimal, such as `+12.5%`.
String percent(int part, int whole) {
  if (whole == 0) return '—';
  final value = part * 100 / whole;
  return '${value > 0 ? '+' : ''}${value.toStringAsFixed(1)}%';
}

/// Taiwan's market colours: red for up, green for down.
Color gainColor(int value) => value > 0
    ? Palette.warn
    : value < 0
    ? Palette.olive
    : Palette.muted;

/// The amount a full-height bar stands for. One very large day, such as
/// rent, is capped near the next largest so the other days stay readable;
/// its bar is drawn with a notch.
int barScale(List<int> days) {
  final sorted = [...days]..sort();
  if (sorted.isEmpty || sorted.last <= 0) return 1;
  if (sorted.length < 2 || sorted[sorted.length - 2] <= 0) return sorted.last;
  return min(sorted.last, (sorted[sorted.length - 2] * 1.4).round());
}

class _BarsPainter extends CustomPainter {
  _BarsPainter({
    required this.days,
    required this.length,
    required this.month,
    required this.selected,
    required this.grow,
    required this.label,
  });

  final List<int> days;
  final int length;
  final int month;
  final int selected;
  final double grow;
  final TextStyle label;

  @override
  void paint(Canvas canvas, Size size) {
    const labels = 18.0;
    const top = 16.0;
    final bottom = size.height - labels;
    final scale = barScale(days);
    final slot = size.width / length;
    final bar = max(2.0, slot * 0.58);
    final muted = label.copyWith(color: Palette.muted);
    for (var day = 1; day <= length; day++) {
      final left = slot * (day - 1) + (slot - bar) / 2;
      if (day > days.length) {
        canvas.drawRRect(
          RRect.fromLTRBR(left, bottom - 3, left + bar, bottom, Radius.zero),
          Paint()..color = Palette.line,
        );
        continue;
      }
      final amount = days[day - 1];
      final share = min(1.0, amount / scale);
      final height = max(2.0, (bottom - top) * share * grow);
      final picked = day == selected;
      final rect = RRect.fromRectAndCorners(
        Rect.fromLTWH(left, bottom - height, bar, height),
        topLeft: Radius.circular(bar / 2),
        topRight: Radius.circular(bar / 2),
      );
      canvas.drawRRect(
        rect,
        Paint()..color = picked ? Palette.clay : Palette.peach,
      );
      if (amount > scale) {
        final notch = bottom - height + 10;
        canvas.drawLine(
          Offset(left - 1, notch),
          Offset(left + bar + 1, notch - 3),
          Paint()
            ..color = Palette.paper
            ..strokeWidth = 2,
        );
      }
    }
    for (final day in {1, 8, 15, 22, length}) {
      paintText(
        canvas,
        '$month/$day',
        muted,
        Offset(slot * (day - 0.5), size.height),
        anchor: const Offset(0.5, 1),
      );
    }
    if (selected < 1 || selected > days.length) return;
    // The chosen day's amount, just above its bar.
    final amount = days[selected - 1];
    final height = max(2.0, (bottom - top) * min(1.0, amount / scale) * grow);
    final x = (slot * (selected - 0.5)).clamp(24.0, size.width - 24);
    paintText(
      canvas,
      compactAmount(amount),
      label.copyWith(color: Palette.clay, fontWeight: FontWeight.w700),
      Offset(x, bottom - height - 2),
      anchor: const Offset(0.5, 1),
    );
  }

  @override
  bool shouldRepaint(_BarsPainter old) =>
      old.selected != selected || old.grow != grow || old.days != days;
}
