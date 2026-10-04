import 'dart:math';

import 'package:flutter/material.dart';

import '../book.dart';
import '../charts/chart_data.dart';
import '../charts/chart_parts.dart';
import '../theme.dart';
import '../ui/kit.dart';

/// The first screen, sized to fit a phone without scrolling: this
/// month's spending against income and the investments on top, then a
/// bar for each day over that day's entries. Tapping a bar
/// shows its day below; only the entries scroll.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.book});

  final Book book;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late int _day = widget.book.today.day;

  /// Below this height the entries would be squeezed out, so the whole
  /// page scrolls instead.
  static const _compact = 560.0;

  @override
  Widget build(BuildContext context) {
    final book = widget.book;
    return ListenableBuilder(
      listenable: book,
      builder: (context, _) => LayoutBuilder(
        builder: (context, constraints) {
          final top = _top(context);
          final day = _dayHeader(context);
          final entries = _entries(context);
          const padding = EdgeInsets.symmetric(horizontal: 16);
          if (constraints.maxHeight < _compact) {
            return ListView(
              padding: padding,
              children: [...top, day, ...entries],
            );
          }
          return Padding(
            padding: padding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...top,
                day,
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

  DateTime get _date {
    final today = widget.book.today;
    return DateTime.utc(today.year, today.month, _day);
  }

  List<Widget> _top(BuildContext context) {
    final book = widget.book;
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(color: Palette.muted);
    return [
      ScreenHeader(
        title: '${book.today.month} 月',
        onTitleTap: () => comingSoon(context, '切換月份'),
        actions: [
          IconButton(
            tooltip: '搜尋',
            onPressed: () => comingSoon(context, '搜尋'),
            icon: const Icon(Icons.search),
          ),
          IconButton(
            tooltip: '提醒',
            onPressed: () => comingSoon(context, '提醒'),
            icon: const Icon(Icons.notifications_none),
          ),
        ],
      ),
      Text('今天也要好好記帳！', style: muted),
      const SizedBox(height: 12),
      IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _MonthPanel(
                expense: book.monthTotal(EntryKind.expense),
                income: book.monthTotal(EntryKind.income),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: _InvestPanel(book)),
          ],
        ),
      ),
      const SizedBox(height: 10),
      if (book.reminders.isNotEmpty) ...[
        _Reminders(book.reminders),
        const SizedBox(height: 12),
      ],
      DailyBars(
        days: book.monthDays,
        length: book.daysInMonth,
        month: book.today.month,
        selected: _day,
        onSelect: (day) => setState(() => _day = day),
      ),
    ];
  }

  Widget _dayHeader(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final date = _date;
    final spent = widget.book.total(date, EntryKind.expense);
    final title = date == widget.book.today ? '今天' : shortDay(date);
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 2),
      child: Row(
        children: [
          Text(title, style: text.titleSmall),
          const Spacer(),
          Text(
            '支出 ${groupDigits(spent)}',
            style: text.bodySmall?.copyWith(color: Palette.muted),
          ),
        ],
      ),
    );
  }

  List<Widget> _entries(BuildContext context) {
    final entries = widget.book.on(_date);
    if (entries.isNotEmpty) {
      return [for (final entry in entries) EntryRow(entry)];
    }
    final text = Theme.of(context).textTheme;
    return [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          '這天沒有記帳',
          style: text.bodyMedium?.copyWith(color: Palette.muted),
        ),
      ),
    ];
  }
}

/// Shows [children] in a sheet from the bottom.
Future<void> _sheet(BuildContext context, String title, List<Widget> children) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Palette.card,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    ),
  );
}

/// One line, 「尚有 2 筆待記」; tap to see them.
class _Reminders extends StatelessWidget {
  const _Reminders(this.items);

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(color: Palette.muted);
    return Panel(
      color: Palette.wash,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      onTap: () => _sheet(context, '待記', [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text('・$item'),
          ),
      ]),
      child: Row(
        children: [
          const Icon(Icons.edit_note, size: 22, color: Palette.clay),
          const SizedBox(width: 8),
          Text('尚有 ${items.length} 筆待記', style: text.bodyMedium),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              items.first,
              style: muted,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Icon(Icons.chevron_right, size: 18, color: Palette.muted),
        ],
      ),
    );
  }
}

/// Spending as a share of income, drawn as a ring.
class _MonthPanel extends StatelessWidget {
  const _MonthPanel({required this.expense, required this.income});

  final int expense;
  final int income;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(color: Palette.muted);
    final share = income == 0 ? 1.0 : expense / income;
    final over = share > 1;
    return Panel(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('本月收支', style: muted),
          const SizedBox(height: 8),
          Row(
            children: [
              SizedBox.square(
                dimension: 52,
                child: CustomPaint(
                  painter: _Ring(share, over: over),
                  child: Center(
                    child: Text(
                      '${(share * 100).round()}%',
                      style: text.labelMedium?.copyWith(
                        color: over ? Palette.warn : Palette.ink,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Figure('支出', expense, Palette.ink),
                    const SizedBox(height: 2),
                    _Figure('收入', income, Palette.clay),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure(this.label, this.amount, this.color);

  final String label;
  final int amount;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label ',
              style: text.bodySmall?.copyWith(color: Palette.muted),
            ),
            TextSpan(
              text: groupDigits(amount),
              style: text.titleSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Ring extends CustomPainter {
  _Ring(this.share, {required this.over});

  final double share;
  final bool over;

  @override
  void paint(Canvas canvas, Size size) {
    const width = 6.0;
    final rect = (Offset.zero & size).deflate(width / 2);
    canvas.drawArc(
      rect,
      0,
      2 * pi,
      false,
      Paint()
        ..color = Palette.wash
        ..style = PaintingStyle.stroke
        ..strokeWidth = width,
    );
    canvas.drawArc(
      rect,
      -pi / 2,
      2 * pi * share.clamp(0.0, 1.0),
      false,
      Paint()
        ..color = over ? Palette.warn : Palette.clay
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = width,
    );
  }

  @override
  bool shouldRepaint(_Ring old) => old.share != share || old.over != over;
}

/// Market value, the gain, and a bar split by holding; tap for details.
class _InvestPanel extends StatelessWidget {
  const _InvestPanel(this.book);

  final Book book;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(color: Palette.muted);
    final value = book.investValue;
    final cost = book.holdings.fold(0, (sum, h) => sum + h.cost);
    final change = book.holdings.fold(0, (sum, h) => sum + h.change);
    final gain = value - cost;
    return Panel(
      padding: const EdgeInsets.all(12),
      onTap: () => _sheet(context, '持股', [
        for (final (i, h) in book.holdings.indexed) _HoldingRow(h, i),
      ]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('投資', style: muted),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              dollars(value),
              style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              '${percent(gain, cost)}　今日 ${signed(change)}',
              style: muted?.copyWith(color: gainColor(gain)),
            ),
          ),
          const Spacer(),
          SizedBox(
            height: 8,
            width: double.infinity,
            child: CustomPaint(
              painter: _Allocation([for (final h in book.holdings) h.value]),
            ),
          ),
        ],
      ),
    );
  }
}

/// Holdings side by side in one thin bar, in the data colours.
class _Allocation extends CustomPainter {
  _Allocation(this.values);

  final List<int> values;

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold(0, (sum, v) => sum + v);
    if (total == 0) return;
    canvas.clipRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(4)),
    );
    var left = 0.0;
    for (final (i, value) in values.indexed) {
      final width = size.width * value / total;
      canvas.drawRect(
        Rect.fromLTWH(left, 0, width - 1.5, size.height),
        Paint()..color = holdingColor(i),
      );
      left += width;
    }
  }

  @override
  bool shouldRepaint(_Allocation old) => old.values != values;
}

Color holdingColor(int index) =>
    Palette.series[index % Palette.series.length];

class _HoldingRow extends StatelessWidget {
  const _HoldingRow(this.holding, this.index);

  final Holding holding;
  final int index;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(color: Palette.muted);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            margin: const EdgeInsets.only(right: 10),
            decoration: BoxDecoration(
              color: holdingColor(index),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          Text(holding.name, style: text.bodyMedium),
          const SizedBox(width: 6),
          Text(holding.code, style: muted),
          const Spacer(),
          Text(
            percent(holding.gain, holding.cost),
            style: muted?.copyWith(color: gainColor(holding.gain)),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 84,
            child: Text(
              groupDigits(holding.value),
              textAlign: TextAlign.end,
              style: text.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

/// A bar for each day of the month. Tap or drag across them to choose a
/// day; the chosen one is drawn in the accent.
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
    return SizedBox(
      height: 96,
      child: LayoutBuilder(
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
      ),
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
    const top = 4.0;
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
  }

  @override
  bool shouldRepaint(_BarsPainter old) =>
      old.selected != selected || old.grow != grow || old.days != days;
}
