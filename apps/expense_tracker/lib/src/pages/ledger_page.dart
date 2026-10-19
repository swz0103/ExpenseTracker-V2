import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../compose/pickers.dart';
import '../look/figures.dart';
import '../look/glyphs.dart';
import '../look/icons.dart';
import '../look/theme.dart';
import '../look/widgets.dart';
import '../model/batch.dart';
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

  /// Entries of this category, its subcategories or a split part in it.
  String? _category;
  String? _search;

  /// The entries picked for a change at once; a long press starts it.
  final _picked = <String>{};

  String get _words => (_search ?? '').trim();

  void _toggle(Entry e) {
    HapticFeedback.selectionClick();
    setState(() {
      if (!_picked.remove(e.id)) _picked.add(e.id);
    });
  }

  List<Entry> get _pickedEntries => [
    for (final e in widget.ledger.entries)
      if (_picked.contains(e.id)) e,
  ];

  /// Says how many of the picked entries a change reached, and ends the
  /// picking.
  void _done(String what, int changed) {
    final total = _picked.length;
    setState(_picked.clear);
    showNote(
      context,
      changed == total
          ? '已$what $changed 筆'
          : '已$what $changed 筆，其餘 ${total - changed} 筆不適用',
    );
  }

  Future<void> _pickCategory() async {
    final ledger = widget.ledger;
    final picked = _pickedEntries;
    final income = picked.every((e) => e.type == EntryType.income);
    final name = await pickOption<String>(
      context,
      title: '改成哪個分類',
      selected: null,
      options: [
        for (final c in ledger.categoriesFor(income: income))
          Option(c.name, c.name, iconFor(c.icon), c.color),
      ],
    );
    if (name == null || !mounted) return;
    _done('改分類', ledger.recategorize(picked, name));
  }

  Future<void> _pickAccount() async {
    final ledger = widget.ledger;
    final picked = _pickedEntries;
    final id = await pickOption<String>(
      context,
      title: '改到哪個帳戶',
      selected: null,
      columns: 3,
      options: [
        for (final a in ledger.openAccounts)
          Option(a.id, a.name, accountIcon(a), accountColor(a.kind)),
      ],
    );
    if (id == null || !mounted) return;
    _done('改帳戶', ledger.moveToAccount(picked, id));
  }

  /// Deletes every picked entry, with one way back for all of them.
  void _removePicked() {
    final ledger = widget.ledger;
    final removed = [
      for (final e in _pickedEntries)
        if (ledger.remove(e.id) case final r?) r,
    ];
    setState(_picked.clear);
    showNote(
      context,
      '已刪除 ${removed.length} 筆',
      action: '復原',
      onAction: () {
        for (final r in removed.reversed) {
          ledger.restore(r);
        }
      },
    );
  }

  /// The month's entries, or every month's that match the search.
  List<Entry> _shown() {
    final (year, month) = _month;
    final words = _words;
    final ledger = widget.ledger;
    final source = words.isEmpty
        ? ledger.entriesIn(year, month)
        : ledger.search(words);
    return [
      for (final e in source)
        if (_kind.shows(e) &&
            (_account == null || e.account == _account || e.to == _account) &&
            (_category == null || _inCategory(e, _category!)))
          e,
    ];
  }

  bool _inCategory(Entry e, String name) =>
      e.category == name ||
      widget.ledger.category(e.category).parent == name ||
      e.parts.any((p) => p.$1 == name);

  Future<void> _filter() async {
    final ledger = widget.ledger;
    var kind = _kind;
    var account = _account;
    var category = _category;
    final applied = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Hue.panel,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) => SafeArea(
          child: SingleChildScrollView(
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
                const SizedBox(height: 14),
                const Text('分類', style: TextStyle(color: Hue.muted)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('全部分類'),
                      selected: category == null,
                      onSelected: (_) => setSheet(() => category = null),
                    ),
                    for (final c in ledger.categories)
                      if (!c.archived && c.parent == null)
                        ChoiceChip(
                          label: Text(c.name),
                          selected: category == c.name,
                          onSelected: (_) => setSheet(() => category = c.name),
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
        _category = category;
      });
    }
  }

  /// Deletes [entry] after a swipe, with a way back.
  void _remove(Entry entry) {
    HapticFeedback.mediumImpact();
    final removed = widget.ledger.remove(entry.id);
    if (removed == null) return;
    showNote(
      context,
      '已刪除「${entry.title}」',
      action: '復原',
      onAction: () => widget.ledger.restore(removed),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ledger = widget.ledger;
    return ListenableBuilder(
      listenable: ledger,
      builder: (context, _) {
        final (year, month) = _month;
        final shown = _shown();
        final searching = _words.isNotEmpty;
        final income = shown.fold(0, (sum, e) => sum + e.earning);
        final expense = shown.fold(0, (sum, e) => sum + e.spending);
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
                total: spentToday == 0 ? null : '支出 ${money(spentToday)}',
              ),
            );
          }
          if (_picked.isNotEmpty) {
            final on = _picked.contains(e.id);
            group.add(
              Container(
                color: on ? Hue.accent.withValues(alpha: 0.12) : null,
                child: EntryTile(
                  ledger: ledger,
                  entry: e,
                  onTap: () => _toggle(e),
                ),
              ),
            );
            continue;
          }
          group.add(
            Dismissible(
              key: ValueKey(e.id),
              direction: DismissDirection.endToStart,
              background: Container(
                color: Hue.danger,
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 20),
                child: const Text(
                  '刪除',
                  style: TextStyle(
                    color: Hue.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              onDismissed: (_) => _remove(e),
              child: GestureDetector(
                onLongPress: () => _toggle(e),
                child: EntryTile(
                  ledger: ledger,
                  entry: e,
                  onTap: () => widget.nav.showEntry(e),
                ),
              ),
            ),
          );
        }
        close();
        final transfers = shown.where((e) => e.type == EntryType.transfer);
        final account = _account;
        final category = _category;
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
            if (_picked.isNotEmpty)
              _PickBar(
                count: _picked.length,
                onCategory: _pickCategory,
                onAccount: _pickAccount,
                onRemove: _removePicked,
                onCancel: () => setState(_picked.clear),
              )
            else
              Tile(
                hero: true,
                icon: Glyph.records,
                label: searching
                    ? '搜尋「$_words」· ${shown.length} 筆'
                    : '$month 月結餘 · ${shown.length} 筆',
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
                      hintText: '搜尋全部紀錄：備註、商家、標籤、金額',
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
            if (category != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: InputChip(
                    label: Text(category),
                    onDeleted: () => setState(() => _category = null),
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

/// What can be done to the picked entries at once.
class _PickBar extends StatelessWidget {
  const _PickBar({
    required this.count,
    required this.onCategory,
    required this.onAccount,
    required this.onRemove,
    required this.onCancel,
  });

  final int count;
  final VoidCallback onCategory;
  final VoidCallback onAccount;
  final VoidCallback onRemove;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    Widget action(String label, VoidCallback onTap, {Color? color}) =>
        TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(foregroundColor: color ?? Hue.accent),
          child: Text(label),
        );
    return SoftPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '已選 $count 筆 · 點紀錄可加選或取消',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                tooltip: '取消',
                onPressed: onCancel,
                icon: const GlyphIcon(Glyph.close, size: 18),
              ),
            ],
          ),
          Wrap(
            spacing: 4,
            children: [
              action('改分類', onCategory),
              action('改帳戶', onAccount),
              action('刪除', onRemove, color: Hue.danger),
            ],
          ),
        ],
      ),
    );
  }
}
