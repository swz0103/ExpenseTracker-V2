import 'package:flutter/material.dart';

import '../compose/pickers.dart';
import '../look/figures.dart';
import '../look/glyphs.dart';
import '../look/haptics.dart';
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

  /// A span of days in place of the month; null shows the month.
  DateTimeRange? _range;

  /// The smallest and largest amount shown; null for no bound.
  int? _least;
  int? _most;

  /// Whether the search field is shown in place of the kind chips.
  var _searchOpen = false;

  /// The entries picked for a change at once; a long press starts it.
  final _picked = <String>{};

  String get _words => (_search ?? '').trim();

  void _toggle(Entry e) {
    Haptics.selection();
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

  /// The month's entries, the chosen days', or every month's that match
  /// the search; newest first.
  List<Entry> _shown() {
    final (year, month) = _month;
    final words = _words;
    final ledger = widget.ledger;
    final range = _range;
    final Iterable<Entry> source;
    if (words.isNotEmpty) {
      source = ledger.search(words);
    } else if (range != null) {
      source = [
        for (
          var m = DateTime.utc(range.end.year, range.end.month);
          !m.isBefore(DateTime.utc(range.start.year, range.start.month));
          m = DateTime.utc(m.year, m.month - 1)
        )
          ...ledger.entriesIn(m.year, m.month),
      ];
    } else {
      source = ledger.entriesIn(year, month);
    }
    bool inRange(Entry e) {
      if (range == null) return true;
      final day = DateTime.utc(e.date.year, e.date.month, e.date.day);
      return !day.isBefore(_utcDay(range.start)) &&
          !day.isAfter(_utcDay(range.end));
    }

    return [
      for (final e in source)
        if (_kind.shows(e) &&
            inRange(e) &&
            (_least == null || e.amount >= _least!) &&
            (_most == null || e.amount <= _most!) &&
            (_account == null || e.account == _account || e.to == _account) &&
            (_category == null || _inCategory(e, _category!)))
          e,
    ];
  }

  static DateTime _utcDay(DateTime d) => DateTime.utc(d.year, d.month, d.day);

  /// The chosen days as words, such as 9/1–10/4.
  String _rangeLabel(DateTimeRange range) =>
      '${range.start.month}/${range.start.day}–'
      '${range.end.month}/${range.end.day}';

  /// The amount bounds as words, such as 100 – 500.
  String _amountLabel() => switch ((_least, _most)) {
    (final least?, final most?) =>
      '金額 ${groupDigits(least)}–${groupDigits(most)}',
    (final least?, null) => '金額 ${groupDigits(least)} 以上',
    (null, final most?) => '金額 ${groupDigits(most)} 以下',
    _ => '',
  };

  bool _inCategory(Entry e, String name) =>
      e.category == name ||
      widget.ledger.category(e.category).parent == name ||
      e.parts.any((p) => p.$1 == name);

  Future<void> _filter() async {
    final ledger = widget.ledger;
    var kind = _kind;
    var account = _account;
    var category = _category;
    var range = _range;
    final least = TextEditingController(text: _least?.toString() ?? '');
    final most = TextEditingController(text: _most?.toString() ?? '');
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
                const Text('日期', style: TextStyle(color: Hue.muted)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('依月份'),
                      selected: range == null,
                      onSelected: (_) => setSheet(() => range = null),
                    ),
                    ChoiceChip(
                      label: Text(range == null ? '自訂區間' : _rangeLabel(range!)),
                      selected: range != null,
                      onSelected: (_) async {
                        final today = ledger.today;
                        final picked = await showDateRangePicker(
                          context: context,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(
                            today.year,
                            today.month,
                            today.day,
                          ),
                          initialDateRange: range,
                          helpText: '選擇日期區間',
                          saveText: '確定',
                        );
                        if (picked != null) setSheet(() => range = picked);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Text('金額', style: TextStyle(color: Hue.muted)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(child: _AmountField(least, '最少')),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10),
                      child: Text('–', style: TextStyle(color: Hue.muted)),
                    ),
                    Expanded(child: _AmountField(most, '最多')),
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
        _range = range;
        _least = int.tryParse(least.text.trim());
        _most = int.tryParse(most.text.trim());
      });
    }
    least.dispose();
    most.dispose();
  }

  /// Deletes [entry] after a swipe, with a way back.
  void _remove(Entry entry) {
    Haptics.medium();
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
        var group = <Entry>[];
        DateTime? day;
        Widget tile(Entry e, {required bool last}) {
          if (_picked.isNotEmpty) {
            return Container(
              color: _picked.contains(e.id)
                  ? Hue.accent.withValues(alpha: 0.12)
                  : null,
              child: EntryTile(
                ledger: ledger,
                entry: e,
                divider: !last,
                onTap: () => _toggle(e),
              ),
            );
          }
          return Dismissible(
            key: ValueKey(e.id),
            direction: DismissDirection.endToStart,
            background: Container(
              color: Hue.danger,
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20),
              child: const Text(
                '刪除',
                style: TextStyle(
                  color: Hue.onAccent,
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
                divider: !last,
                onTap: () => widget.nav.showEntry(e),
              ),
            ),
          );
        }

        void close() {
          if (group.isEmpty) return;
          rows.add(
            SoftPanel(
              color: Hue.white,
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Column(
                children: [
                  for (final (i, e) in group.indexed)
                    tile(e, last: i == group.length - 1),
                ],
              ),
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
          group.add(e);
        }
        close();
        final transfers = shown.where((e) => e.type == EntryType.transfer);
        final account = _account;
        final category = _category;
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
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
                    : switch (_range) {
                        final range? =>
                          '${_rangeLabel(range)} 結餘 · ${shown.length} 筆',
                        null => '$month 月結餘 · ${shown.length} 筆',
                      },
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
            if (_searchOpen)
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: '搜尋備註、商家、標籤、金額',
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
                  _RoundButton(
                    tooltip: '關閉搜尋',
                    glyph: Glyph.close,
                    onTap: () => setState(() {
                      _searchOpen = false;
                      _search = null;
                    }),
                  ),
                ],
              )
            else
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 36,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          for (final option in KindFilter.values)
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: GestureDetector(
                                onTap: () => setState(() => _kind = option),
                                child: Container(
                                  // Narrow enough for all five beside
                                  // the search and filter buttons.
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 11,
                                  ),
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: option == _kind
                                        ? Hue.accent
                                        : Hue.tile,
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  child: Text(
                                    option.label,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: option == _kind
                                          ? Hue.onAccent
                                          : Hue.accent,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  _RoundButton(
                    tooltip: '搜尋',
                    glyph: Glyph.search,
                    onTap: () => setState(() => _searchOpen = true),
                  ),
                  _RoundButton(
                    tooltip: '篩選',
                    glyph: Glyph.sliders,
                    onTap: _filter,
                  ),
                ],
              ),
            if (_range != null || _least != null || _most != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 8,
                  children: [
                    if (_range case final range?)
                      InputChip(
                        label: Text(_rangeLabel(range)),
                        onDeleted: () => setState(() => _range = null),
                      ),
                    if (_least != null || _most != null)
                      InputChip(
                        label: Text(_amountLabel()),
                        onDeleted: () => setState(() {
                          _least = null;
                          _most = null;
                        }),
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

/// A bound for the amount filter, digits only.
class _AmountField extends StatelessWidget {
  const _AmountField(this.controller, this.hint);

  final TextEditingController controller;
  final String hint;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    keyboardType: TextInputType.number,
    decoration: InputDecoration(
      hintText: hint,
      isDense: true,
      filled: true,
      fillColor: Hue.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    ),
  );
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

/// A small round button beside the chips: search, filter, close.
class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.tooltip,
    required this.glyph,
    required this.onTap,
  });

  final String tooltip;
  final Glyph glyph;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 6),
    child: Material(
      color: Hue.white,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onTap,
        visualDensity: VisualDensity.compact,
        icon: GlyphIcon(glyph, size: 18),
      ),
    ),
  );
}
