import 'dart:math';

import 'package:flutter/material.dart';

import '../book.dart';
import '../charts/chart_data.dart';
import '../charts/chart_parts.dart';
import '../theme.dart';
import '../ui/kit.dart';

/// The first screen: this month's spending and income, a bar for each
/// day, quick ways to record, reminders, investments and today's entries.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.book, required this.onRecord});

  final Book book;

  /// Opens the editor for a new entry of this kind.
  final ValueChanged<EntryKind> onRecord;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = text.bodyMedium?.copyWith(color: Palette.muted);
    return ListenableBuilder(
      listenable: book,
      builder: (context, _) {
        final today = book.on(book.today);
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
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
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _Stat('本月支出', book.monthTotal(EntryKind.expense)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _Stat('本月收入', book.monthTotal(EntryKind.income)),
                ),
              ],
            ),
            const SizedBox(height: 20),
            DailyBars(
              days: book.monthDays,
              length: book.daysInMonth,
              month: book.today.month,
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _Action(Icons.payments_outlined, '支出', () {
                  onRecord(EntryKind.expense);
                }),
                _Action(Icons.savings_outlined, '收入', () {
                  onRecord(EntryKind.income);
                }),
                _Action(Icons.swap_horiz, '轉帳', () {
                  onRecord(EntryKind.transfer);
                }),
                _Action(Icons.qr_code_scanner, '掃描', () {
                  comingSoon(context, '掃描發票');
                }),
              ],
            ),
            const SizedBox(height: 20),
            if (book.reminders.isNotEmpty) ...[
              _Reminders(book.reminders),
              const SizedBox(height: 12),
            ],
            _Investments(book),
            const SizedBox(height: 20),
            Row(
              children: [
                Text('今天', style: text.titleSmall),
                const Spacer(),
                Text(shortDay(book.today), style: text.bodySmall),
              ],
            ),
            const SizedBox(height: 4),
            if (today.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text('今天還沒有記帳', style: muted),
              ),
            for (final entry in today) EntryRow(entry),
          ],
        );
      },
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.amount);

  final String label;
  final int amount;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Panel(
      color: Palette.wash,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: text.bodySmall?.copyWith(color: Palette.muted)),
          const SizedBox(height: 6),
          Text(
            dollars(amount),
            style: text.titleLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action(this.icon, this.label, this.onTap);

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          children: [
            IconTile(icon, size: 48),
            const SizedBox(height: 6),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _Reminders extends StatelessWidget {
  const _Reminders(this.items);

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Panel(
      color: Palette.wash,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('尚有 ${items.length} 筆待記', style: text.titleSmall),
                const SizedBox(height: 6),
                for (final item in items)
                  Text(
                    '・$item',
                    style: text.bodySmall?.copyWith(color: Palette.muted),
                  ),
              ],
            ),
          ),
          const Icon(Icons.edit_note, size: 40, color: Palette.peach),
        ],
      ),
    );
  }
}

class _Investments extends StatefulWidget {
  const _Investments(this.book);

  final Book book;

  @override
  State<_Investments> createState() => _InvestmentsState();
}

class _InvestmentsState extends State<_Investments> {
  var _open = false;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(color: Palette.muted);
    final book = widget.book;
    final value = book.investValue;
    final cost = book.holdings.fold(0, (sum, h) => sum + h.cost);
    final change = book.holdings.fold(0, (sum, h) => sum + h.change);
    final gain = value - cost;
    final summary =
        '${percent(gain, cost)}（${signed(gain)}）　今日 ${signed(change)}';
    return Panel(
      onTap: () => setState(() => _open = !_open),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('投資總資產', style: muted),
                    const SizedBox(height: 4),
                    Text(
                      dollars(value),
                      style: text.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      summary,
                      style: muted?.copyWith(color: gainColor(gain)),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 110,
                height: 48,
                child: CustomPaint(
                  painter: _Sparkline(book.investHistory),
                ),
              ),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _open
                ? Column(
                    children: [
                      const SizedBox(height: 8),
                      for (final h in book.holdings) _HoldingRow(h),
                    ],
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

class _HoldingRow extends StatelessWidget {
  const _HoldingRow(this.holding);

  final Holding holding;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(color: Palette.muted);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
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
    ? const Color(0xFFD0603F)
    : value < 0
    ? Palette.olive
    : Palette.muted;

class _Sparkline extends CustomPainter {
  _Sparkline(this.values);

  final List<int> values;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final high = values.reduce(max);
    final low = values.reduce(min);
    final span = max(1, high - low);
    Offset at(int i) => Offset(
      size.width * i / (values.length - 1),
      size.height - 4 - (size.height - 8) * (values[i] - low) / span,
    );
    final line = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < values.length; i++) {
      line.lineTo(at(i).dx, at(i).dy);
    }
    final rising = values.last >= values.first;
    final color = gainColor(rising ? 1 : -1);
    final area = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.18), color.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_Sparkline old) => old.values != values;
}

/// A bar for each day of the month; tap or drag to read a day.
class DailyBars extends StatefulWidget {
  const DailyBars({
    super.key,
    required this.days,
    required this.length,
    required this.month,
  });

  /// Spending on each day so far, the 1st first.
  final List<int> days;

  /// Days in the month.
  final int length;
  final int month;

  @override
  State<DailyBars> createState() => _DailyBarsState();
}

class _DailyBarsState extends State<DailyBars> {
  int? _day;

  void _pick(Offset at, double width) {
    final day = (at.dx / width * widget.length).floor() + 1;
    final last = max(1, widget.days.length);
    final known = day.clamp(1, last);
    if (known != _day) setState(() => _day = known);
  }

  @override
  Widget build(BuildContext context) {
    final label = Theme.of(context).textTheme.labelSmall!;
    return SizedBox(
      height: 150,
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
                  days: widget.days,
                  length: widget.length,
                  month: widget.month,
                  selected: _day ?? widget.days.length,
                  showTip: _day != null,
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
    required this.showTip,
    required this.grow,
    required this.label,
  });

  final List<int> days;
  final int length;
  final int month;
  final int selected;
  final bool showTip;
  final double grow;
  final TextStyle label;

  @override
  void paint(Canvas canvas, Size size) {
    const labels = 18.0;
    const top = 26.0;
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
    if (!showTip || selected < 1 || selected > days.length) return;
    final tip = '$month/$selected  ${dollars(days[selected - 1])}';
    final painter = layoutText(tip, label.copyWith(color: Palette.card));
    final width = painter.width + 16;
    final centre = slot * (selected - 0.5);
    final left = (centre - width / 2).clamp(0.0, size.width - width);
    final box = RRect.fromLTRBR(
      left,
      0,
      left + width,
      painter.height + 8,
      const Radius.circular(8),
    );
    canvas.drawRRect(box, Paint()..color = Palette.ink);
    painter.paint(canvas, Offset(left + 8, 4));
    painter.dispose();
  }

  @override
  bool shouldRepaint(_BarsPainter old) =>
      old.selected != selected ||
      old.showTip != showTip ||
      old.grow != grow ||
      old.days != days;
}
