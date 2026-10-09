import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../demo/ledger.dart';
import '../look/figures.dart';
import '../look/theme.dart';
import '../look/widgets.dart';
import 'entry_tile.dart';
import 'nav.dart';

/// Kinds the record list can be narrowed to.
enum KindFilter {
  all('全部'),
  expense('支出'),
  income('收入'),
  transfer('轉帳'),
  investment('投資');

  const KindFilter(this.label);

  final String label;

  bool shows(Entry e) => switch (this) {
    all => true,
    expense => e.type == EntryType.expense,
    income => e.type == EntryType.income || e.type == EntryType.dividend,
    transfer => e.type == EntryType.transfer,
    investment => e.isInvestment,
  };
}

/// 收支紀錄: the month's income against spending, then every entry by
/// day, with search, filters and a CSV copy.
class LedgerPage extends StatefulWidget {
  const LedgerPage({super.key, required this.ledger, required this.nav});

  final Ledger ledger;
  final Nav nav;

  @override
  State<LedgerPage> createState() => _LedgerPageState();
}

class _LedgerPageState extends State<LedgerPage> {
  late var _month = (widget.ledger.today.year, widget.ledger.today.month);
  var _kind = KindFilter.all;
  String? _account;
  String? _search;

  List<Entry> _shown() {
    final (year, month) = _month;
    final words = (_search ?? '').trim();
    return [
      for (final e in widget.ledger.entriesIn(year, month))
        if (_kind.shows(e) &&
            (_account == null || e.account == _account || e.to == _account) &&
            (words.isEmpty ||
                e.note.contains(words) ||
                e.category.contains(words)))
          e,
    ];
  }

  Future<void> _filter() async {
    final ledger = widget.ledger;
    var kind = _kind;
    var account = _account;
    final applied = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Hue.panel,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '篩選',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 14),
                const Text('類型', style: TextStyle(color: Hue.muted)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final option in KindFilter.values)
                      ChoiceChip(
                        label: Text(option.label),
                        selected: option == kind,
                        onSelected: (_) => setSheet(() => kind = option),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                const Text('帳戶', style: TextStyle(color: Hue.muted)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('全部帳戶'),
                      selected: account == null,
                      onSelected: (_) => setSheet(() => account = null),
                    ),
                    for (final a in ledger.accounts)
                      ChoiceChip(
                        label: Text(a.name),
                        selected: account == a.id,
                        onSelected: (_) => setSheet(() => account = a.id),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('套用'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (applied == true) {
      setState(() {
        _kind = kind;
        _account = account;
      });
    }
  }

  Future<void> _export() async {
    final ledger = widget.ledger;
    final (year, month) = _month;
    final entries = ledger.entriesIn(year, month);
    final lines = [
      '日期,類型,金額,帳戶,分類,備註',
      for (final e in entries.reversed)
        [
          '${e.date.year}-${e.date.month}-${e.date.day}',
          e.type.name,
          '${e.amount}',
          ledger.account(e.account).name,
          e.category,
          e.note.replaceAll(',', '，'),
        ].join(','),
    ];
    await Clipboard.setData(ClipboardData(text: lines.join('\n')));
    if (!mounted) return;
    showNote(context, '已複製 $year 年 $month 月 ${entries.length} 筆紀錄的 CSV');
  }

  @override
  Widget build(BuildContext context) {
    final ledger = widget.ledger;
    return ListenableBuilder(
      listenable: ledger,
      builder: (context, _) {
        final (year, month) = _month;
        final income = ledger.income(year, month);
        final expense = ledger.expense(year, month);
        final shown = _shown();
        final rows = <Widget>[];
        DateTime? day;
        for (final e in shown) {
          if (e.date != day) {
            day = e.date;
            rows.add(DayHeading(e.date));
          }
          rows.add(
            EntryTile(
              ledger: ledger,
              entry: e,
              onTap: () => widget.nav.showEntry(e),
            ),
          );
        }
        final account = _account;
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          children: [
            PageHeader(
              '收支紀錄',
              trailing: MonthSwitch(
                month: _month,
                latest: (ledger.today.year, ledger.today.month),
                onChanged: (m) => setState(() => _month = m),
              ),
            ),
            Row(
              children: [
                const Text(
                  '本月收支',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                const Text(
                  '結餘 ',
                  style: TextStyle(fontSize: 12, color: Hue.muted),
                ),
                Text(
                  groupDigits(income - expense),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: income < expense ? Hue.negative : Hue.positive,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _Pair('收入', income, Hue.positive),
                const Spacer(),
                _Pair('支出', expense, Hue.negative),
              ],
            ),
            const SizedBox(height: 8),
            Rail(income: income, expense: expense),
            const SizedBox(height: 14),
            const Divider(),
            Row(
              children: [
                Text(
                  '本月紀錄 · ${shown.length} 筆',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => setState(() {
                    _search = _search == null ? '' : null;
                  }),
                  icon: const Icon(Icons.search, size: 18),
                  label: const Text('搜尋'),
                  style: TextButton.styleFrom(foregroundColor: Hue.muted),
                ),
                TextButton.icon(
                  onPressed: _filter,
                  icon: const Icon(Icons.tune, size: 18),
                  label: const Text('篩選'),
                  style: TextButton.styleFrom(foregroundColor: Hue.muted),
                ),
                IconButton(
                  tooltip: '複製 CSV',
                  onPressed: _export,
                  icon: const Icon(Icons.download_outlined, color: Hue.muted),
                ),
              ],
            ),
            if (_search != null)
              TextField(
                autofocus: true,
                decoration: InputDecoration(
                  hintText: '搜尋名稱、分類',
                  isDense: true,
                  filled: true,
                  fillColor: Hue.surface,
                  prefixIcon: const Icon(Icons.search, size: 18),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (text) => setState(() => _search = text),
              ),
            if (_kind != KindFilter.all || account != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 8,
                  children: [
                    if (_kind != KindFilter.all)
                      InputChip(
                        label: Text(_kind.label),
                        onDeleted: () =>
                            setState(() => _kind = KindFilter.all),
                      ),
                    if (account != null)
                      InputChip(
                        label: Text(ledger.account(account).name),
                        onDeleted: () => setState(() => _account = null),
                      ),
                  ],
                ),
              ),
            if (rows.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: Text('沒有符合的紀錄', style: TextStyle(color: Hue.muted)),
                ),
              ),
            ...rows,
          ],
        );
      },
    );
  }
}

class _Pair extends StatelessWidget {
  const _Pair(this.label, this.amount, this.color);

  final String label;
  final int amount;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label  ',
            style: const TextStyle(fontSize: 12, color: Hue.muted),
          ),
          TextSpan(
            text: groupDigits(amount),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
