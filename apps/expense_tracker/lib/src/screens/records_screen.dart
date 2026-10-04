import 'package:flutter/material.dart';

import '../book.dart';
import '../charts/chart_data.dart';
import '../theme.dart';
import '../ui/kit.dart';

/// Every entry of a month, newest day first; the filter button narrows
/// it to one kind.
class RecordsScreen extends StatefulWidget {
  const RecordsScreen({super.key, required this.book});

  final Book book;

  @override
  State<RecordsScreen> createState() => _RecordsScreenState();
}

class _RecordsScreenState extends State<RecordsScreen> {
  late var _month = (widget.book.today.year, widget.book.today.month);
  var _filter = 0;

  static const _filters = ['全部', '支出', '收入', '轉帳'];

  bool _shows(Entry entry) => switch (_filter) {
    1 => entry.kind == EntryKind.expense,
    2 => entry.kind == EntryKind.income,
    3 => entry.kind == EntryKind.transfer,
    _ => true,
  };

  Future<void> _pickFilter() async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Palette.card,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('篩選')),
            for (final (i, label) in _filters.indexed)
              ListTile(
                title: Text(label),
                trailing: i == _filter
                    ? const Icon(Icons.check, color: Palette.clay)
                    : null,
                onTap: () => Navigator.of(context).pop(i),
              ),
          ],
        ),
      ),
    );
    if (picked != null) setState(() => _filter = picked);
  }

  Future<void> _pickMonth() async {
    final picked = await showModalBottomSheet<(int, int)>(
      context: context,
      backgroundColor: Palette.card,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (year, month) in widget.book.months)
              ListTile(
                title: Text('$year 年 $month 月'),
                trailing: (year, month) == _month
                    ? const Icon(Icons.check, color: Palette.clay)
                    : null,
                onTap: () => Navigator.of(context).pop((year, month)),
              ),
          ],
        ),
      ),
    );
    if (picked != null) setState(() => _month = picked);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final book = widget.book;
    return ListenableBuilder(
      listenable: book,
      builder: (context, _) {
        final (year, month) = _month;
        final groups = [
          for (final date in book.datesIn(year, month))
            (date, book.on(date).where(_shows).toList()),
        ].where((group) => group.$2.isNotEmpty).toList();
        final kind = _filter == 0 ? '' : _filters[_filter];
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ScreenHeader(
                title: '$month 月',
                onTitleTap: _pickMonth,
                actions: [
                  IconButton(
                    tooltip: '搜尋',
                    onPressed: () => comingSoon(context, '搜尋'),
                    icon: const Icon(Icons.search),
                  ),
                  IconButton(
                    tooltip: '篩選',
                    onPressed: _pickFilter,
                    icon: Icon(
                      Icons.tune,
                      color: _filter == 0 ? null : Palette.clay,
                    ),
                  ),
                ],
              ),
              if (_filter != 0)
                Align(
                  alignment: Alignment.centerLeft,
                  child: InputChip(
                    label: Text('只看$kind'),
                    onDeleted: () => setState(() => _filter = 0),
                    backgroundColor: Palette.wash,
                    side: BorderSide.none,
                  ),
                ),
              Expanded(
                child: groups.isEmpty
                    ? Center(
                        child: Text(
                          '這個月沒有$kind紀錄',
                          style: text.bodyMedium?.copyWith(
                            color: Palette.muted,
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 24),
                        itemCount: groups.length,
                        itemBuilder: (context, index) {
                          final (date, entries) = groups[index];
                          return _DayGroup(date, entries);
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DayGroup extends StatelessWidget {
  const _DayGroup(this.date, this.entries);

  final DateTime date;
  final List<Entry> entries;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: Palette.muted);
    final spent = entries
        .where((e) => e.kind == EntryKind.expense)
        .fold(0, (sum, e) => sum + e.amount);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Palette.wash.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Text(shortDay(date), style: style),
              const Spacer(),
              if (spent > 0) Text('支出 ${groupDigits(spent)}', style: style),
            ],
          ),
        ),
        for (final entry in entries) EntryRow(entry),
      ],
    );
  }
}
