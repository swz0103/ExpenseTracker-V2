import 'package:flutter/material.dart';

import '../book.dart';
import '../charts/chart_data.dart';
import '../theme.dart';
import '../ui/kit.dart';
import '../ui/mini_charts.dart';
import 'home_screen.dart' show signed;

/// Net worth, how it moved over the year and what it is made of, then
/// every account as a tile, two to a row.
class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key, required this.book});

  final Book book;

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  int? _month;

  static const _groups = [
    ('現金與存款', {'現金', '銀行', '電子票證'}),
    ('信用卡', {'信用卡'}),
    ('投資', {'證券'}),
  ];

  @override
  Widget build(BuildContext context) {
    final book = widget.book;
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(color: Palette.muted);
    final stocks = book.investValue;
    List<AccountLine> linesOf(Set<String> kinds) => [
      for (final a in book.accounts)
        if (kinds.contains(a.kind)) a,
    ];
    int sum(List<AccountLine> lines) =>
        lines.fold(0, (total, a) => total + a.balance);
    final cash = sum(linesOf(_groups[0].$2));
    final debt = sum(linesOf(_groups[1].$2));
    final invested = sum(linesOf(_groups[2].$2)) + stocks;
    final worth = cash + debt + invested;
    final parts = [('現金與存款', cash), ('投資', invested)];
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        ScreenHeader(
          title: '帳戶',
          actions: [
            IconButton(
              tooltip: '新增帳戶',
              onPressed: () => comingSoon(context, '新增帳戶'),
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        Text('淨資產', style: muted),
        const SizedBox(height: 2),
        Text(
          dollars(worth),
          style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        _WorthTrend(
          history: book.history,
          selected: _month,
          onSelect: (index) => setState(() => _month = index),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 10,
          width: double.infinity,
          child: CustomPaint(
            painter: _Split([for (final (_, value) in parts) value]),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 16,
          runSpacing: 4,
          children: [
            for (final (i, (name, value)) in parts.indexed)
              _Legend(_splitColor(i), name, groupDigits(value)),
            if (debt < 0) _Legend(Palette.warn, '負債', groupDigits(-debt)),
          ],
        ),
        const SizedBox(height: 20),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.55,
          children: [
            for (final (_, kinds) in _groups)
              for (final line in linesOf(kinds))
                _AccountTile(
                  icon: accountIcon(line.kind),
                  name: line.name,
                  note: line.kind,
                  balance: line.balance,
                  onTap: () => comingSoon(context, line.name),
                ),
            _AccountTile(
              icon: Icons.trending_up,
              name: '股票市值',
              note: '${book.holdings.length} 檔',
              balance: stocks,
              onTap: () => comingSoon(context, '投資'),
            ),
          ],
        ),
      ],
    );
  }
}

/// Net worth at each month end, with the chosen month's change written
/// over the line.
class _WorthTrend extends StatelessWidget {
  const _WorthTrend({
    required this.history,
    required this.selected,
    required this.onSelect,
  });

  final List<MonthPoint> history;
  final int? selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    if (history.isEmpty) return const SizedBox.shrink();
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(color: Palette.muted);
    final last = history.length - 1;
    final picked = (selected ?? last).clamp(0, last);
    final shown = history[picked];
    final before = picked == 0 ? shown : history[picked - 1];
    final change = shown.netWorth - before.netWorth;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            style: muted,
            children: [
              TextSpan(text: '${shown.year}/${shown.month} 月底　比上月 '),
              TextSpan(
                text: signed(change),
                style: TextStyle(
                  color: change < 0 ? Palette.warn : Palette.clay,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 96,
          child: LineChart(
            values: [for (final m in history) m.netWorth],
            selected: picked,
            labels: {0: history.first.label, last: history.last.label},
            onSelect: onSelect,
          ),
        ),
      ],
    );
  }
}

Color _splitColor(int index) => index == 0 ? Palette.clay : Palette.peach;

class _Split extends CustomPainter {
  _Split(this.values);

  final List<int> values;

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold(0, (sum, v) => sum + v);
    if (total <= 0) return;
    canvas.clipRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(5)),
    );
    var left = 0.0;
    for (final (i, value) in values.indexed) {
      final width = size.width * value / total;
      canvas.drawRect(
        Rect.fromLTWH(left, 0, width - 2, size.height),
        Paint()..color = _splitColor(i),
      );
      left += width;
    }
  }

  @override
  bool shouldRepaint(_Split old) => old.values != values;
}

class _Legend extends StatelessWidget {
  const _Legend(this.color, this.name, this.amount);

  final Color color;
  final String name;
  final String amount;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(name, style: style?.copyWith(color: Palette.muted)),
        const SizedBox(width: 4),
        Text(amount, style: style),
      ],
    );
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({
    required this.icon,
    required this.name,
    required this.note,
    required this.balance,
    required this.onTap,
  });

  final IconData icon;
  final String name;
  final String note;
  final int balance;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Material(
      color: Palette.wash,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 18, color: Palette.clay),
                  const SizedBox(width: 6),
                  Text(
                    note,
                    style: text.bodySmall?.copyWith(color: Palette.muted),
                  ),
                ],
              ),
              const Spacer(),
              Text(name, style: text.bodyMedium),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  dollars(balance),
                  style: text.titleMedium?.copyWith(
                    color: balance < 0 ? Palette.warn : Palette.ink,
                    fontWeight: FontWeight.w600,
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
