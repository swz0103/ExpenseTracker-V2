import 'package:flutter/material.dart';

import '../look/figures.dart';
import '../look/glyphs.dart';
import '../look/theme.dart';
import '../look/widgets.dart';
import '../model/ledger.dart';
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
/// day, with search and filters; 設定 exports it.
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
                e.merchant.contains(words) ||
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
        var group = <Widget>[];
        DateTime? day;
        void close() {
          if (group.isEmpty) return;
          rows.add(
            SoftPanel(
              color: Hue.white,
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Column(children: group),
            ),
          );
          group = [];
        }

        for (final e in shown) {
          if (e.date != day) {
            close();
            day = e.date;
            final spentToday = ledger.spentOn(e.date);
            rows.add(
              DayHeading(
                e.date,
                total: spentToday == 0
                    ? null
                    : '支出 ${money(spentToday)}',
              ),
            );
          }
          group.add(
            EntryTile(
              ledger: ledger,
              entry: e,
              onTap: () => widget.nav.showEntry(e),
            ),
          );
        }
        close();
        final transfers = shown.where((e) => e.type == EntryType.transfer);
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
            Tile(
              hero: true,
              icon: Glyph.records,
              label: '$month 月結餘 · ${shown.length} 筆',
              value: money(income - expense),
              valueColor: income < expense ? Hue.negative : Hue.ink,
              size: 28,
              child: TileStats([
                (Glyph.income, '收入', money(income), Hue.positive),
                (Glyph.payout, '支出', money(expense), Hue.negative),
                (Glyph.transfer, '轉帳', '${transfers.length} 筆', Hue.ink),
              ]),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: '搜尋名稱、分類、商家',
                      isDense: true,
                      filled: true,
                      fillColor: Hue.white,
                      prefixIcon: const Padding(
                        padding: EdgeInsets.all(10),
                        child: GlyphIcon(Glyph.search, size: 18),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (text) => setState(() => _search = text),
                  ),
                ),
                const SizedBox(width: 8),
                Material(
                  color: Hue.white,
                  borderRadius: BorderRadius.circular(14),
                  child: IconButton(
                    tooltip: '篩選',
                    onPressed: _filter,
                    icon: const GlyphIcon(Glyph.sliders, size: 18),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 32,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final option in KindFilter.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: GestureDetector(
                        onTap: () => setState(() => _kind = option),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: option == _kind ? Hue.accent : Hue.tile,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            option.label,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: option == _kind ? Hue.white : Hue.accent,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (account != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: InputChip(
                    label: Text(ledger.account(account).name),
                    onDeleted: () => setState(() => _account = null),
                  ),
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
