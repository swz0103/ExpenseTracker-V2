import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/ui/pickers.dart';
import '../../../core/look/figures.dart';
import '../../../core/look/glyphs.dart';
import '../../../core/look/haptics.dart';
import '../../../core/look/theme.dart';
import '../../../core/look/widgets.dart';
import '../../../core/ledger/batch.dart';
import '../../../core/ledger/ledger.dart';
import '../../../core/ui/entry_tile.dart';
import 'ledger_filter_sheet.dart';
import '../../../core/nav.dart';

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
  var _filter = const LedgerFilter();

  /// The words searched for, once typing has paused.
  String? _search;

  /// Waits for a pause in typing before searching, so each letter does
  /// not go through every entry.
  Timer? _typing;

  /// Whether the search field is shown in place of the kind chips.
  var _searchOpen = false;

  /// What is typed in the search field, kept here rather than in the
  /// field: the field is a line of the list, and lines scrolled far away
  /// are let go and built again.
  final _searchText = TextEditingController();

  /// The search field's focus: asked for once when the search opens, not
  /// each time the field is built again.
  final _searchFocus = FocusNode();

  /// The entries picked for a change at once; a long press starts it.
  final _picked = <String>{};

  String get _words => (_search ?? '').trim();

  @override
  void dispose() {
    _typing?.cancel();
    _searchText.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _typed(String text) {
    _typing?.cancel();
    _typing = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _search = text);
    });
  }

  void _openSearch() {
    setState(() => _searchOpen = true);
    // The field is there after this frame; the keyboard comes up once.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _searchOpen) _searchFocus.requestFocus();
    });
  }

  void _closeSearch() {
    _typing?.cancel();
    _searchText.clear();
    _searchFocus.unfocus();
    setState(() {
      _searchOpen = false;
      _search = null;
    });
  }

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
      options: categoryOptions(ledger, income: income),
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
      options: accountOptions(ledger),
    );
    if (id == null || !mounted) return;
    _done('改帳戶', ledger.moveToAccount(picked, id));
  }

  /// Deletes every picked entry as one change, with one way back for all
  /// of them. When the ledger refuses (a later sale would be short of
  /// shares) nothing is taken, the ledger says why, and the picks stay.
  void _removePicked() {
    final ledger = widget.ledger;
    final removed = ledger.removeAll(_picked);
    if (removed.isEmpty) {
      if (_pickedEntries.isEmpty) setState(_picked.clear);
      return;
    }
    setState(_picked.clear);
    showNote(
      context,
      '已刪除 ${removed.length} 筆',
      action: '復原',
      onAction: () => ledger.restoreAll(removed),
    );
  }

  /// The month's entries, the chosen days', or every month's that match
  /// the search; newest first. Entries are read from the ledger's months,
  /// only those the month or the chosen days cover.
  List<Entry> _shown() {
    final (year, month) = _month;
    final words = _words;
    final ledger = widget.ledger;
    final filter = _filter;
    final range = filter.range;
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
    return [
      for (final e in source)
        if (filter.shows(ledger, e)) e,
    ];
  }

  Future<void> _openFilter() async {
    final applied = await showLedgerFilter(context, widget.ledger, _filter);
    if (applied != null && mounted) setState(() => _filter = applied);
  }

  /// Deletes [entry] when a swipe ends, with a way back. False when the
  /// ledger refuses, so the line slides back rather than staying gone
  /// from the screen while the entry is still in the book.
  bool _remove(Entry entry) {
    Haptics.medium();
    final removed = widget.ledger.remove(entry.id);
    if (removed == null) return false;
    showNote(
      context,
      '已刪除「${entry.title}」',
      action: '復原',
      onAction: () => widget.ledger.restore(removed),
    );
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final ledger = widget.ledger;
    return ListenableBuilder(
      listenable: ledger,
      builder: (context, _) {
        final shown = _shown();
        // The list as lines: each day's heading, then its entries on one
        // card. Only the lines on screen are built.
        final items = <_Item>[];
        DateTime? day;
        var group = <Entry>[];
        for (final e in shown) {
          if (e.date != day) {
            day = e.date;
            group = [];
            items
              ..add(_Heading(e.date))
              ..add(_Group(group));
          }
          group.add(e);
        }
        final head = _head(shown);
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          itemCount: head.length + items.length,
          itemBuilder: (context, i) =>
              i < head.length ? head[i] : _line(items[i - head.length]),
        );
      },
    );
  }

  /// What sits above the entries: the title and month, the month's sums
  /// or what to do with the picked entries, the kinds, search and filters.
  List<Widget> _head(List<Entry> shown) {
    final ledger = widget.ledger;
    final (_, month) = _month;
    final filter = _filter;
    final words = _words;
    final searching = words.isNotEmpty;
    final income = shown.fold(0, (sum, e) => sum + e.earning);
    final expense = shown.fold(0, (sum, e) => sum + e.spending);
    final transfers = shown.where((e) => e.type == EntryType.transfer);
    final account = filter.account;
    final category = filter.category;
    return [
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
        BalanceHero(
          ledger: ledger,
          icon: Glyph.records,
          label: searching
              ? '搜尋「$words」· ${shown.length} 筆'
              : switch (filter.range) {
                  final range? =>
                    '${LedgerFilter.rangeLabel(range)} 結餘 · ${shown.length} 筆',
                  null => '$month 月結餘 · ${shown.length} 筆',
                },
          income: income,
          expense: expense,
          third: (Glyph.transfer, '轉帳', '${transfers.length} 筆', Hue.ink),
          rate: false,
          size: 28,
        ),
      const SizedBox(height: 10),
      if (_searchOpen)
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchText,
                focusNode: _searchFocus,
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
                onChanged: _typed,
              ),
            ),
            _RoundButton(
              tooltip: '關閉搜尋',
              glyph: Glyph.close,
              onTap: _closeSearch,
            ),
          ],
        )
      else
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final (i, option) in KindFilter.values.indexed)
                      Padding(
                        // Five 48 dp targets fit beside the search and
                        // filter buttons.
                        padding: EdgeInsets.only(left: i == 0 ? 0 : 3),
                        child: ChoicePill(
                          label: option.label,
                          selected: option == filter.kind,
                          onTap: () => setState(
                            () => _filter = _filter.withKind(option),
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
              onTap: _openSearch,
            ),
            _RoundButton(
              tooltip: '篩選',
              glyph: Glyph.sliders,
              onTap: _openFilter,
            ),
          ],
        ),
      if (filter.range != null || filter.boundsAmount)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Wrap(
            spacing: 8,
            children: [
              if (filter.range case final range?)
                ChoicePill.removable(
                  label: LedgerFilter.rangeLabel(range),
                  onRemove: () =>
                      setState(() => _filter = _filter.withoutRange()),
                ),
              if (filter.boundsAmount)
                ChoicePill.removable(
                  label: filter.amountLabel,
                  onRemove: () =>
                      setState(() => _filter = _filter.withoutAmounts()),
                ),
            ],
          ),
        ),
      if (account != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: ChoicePill.removable(
              label: ledger.account(account).name,
              onRemove: () =>
                  setState(() => _filter = _filter.withoutAccount()),
            ),
          ),
        ),
      if (category != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: ChoicePill.removable(
              label: category,
              onRemove: () =>
                  setState(() => _filter = _filter.withoutCategory()),
            ),
          ),
        ),
      if (shown.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Center(
            child: Text('沒有符合的紀錄', style: TextStyle(color: Hue.muted)),
          ),
        ),
    ];
  }

  /// A line of the list: a day's heading with what was spent, or the
  /// day's entries on a white card.
  Widget _line(_Item item) => switch (item) {
    _Heading(:final day) => _heading(day),
    _Group(:final entries) => SoftPanel(
      color: Hue.white,
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        children: [
          for (final (i, e) in entries.indexed)
            _tile(e, last: i == entries.length - 1),
        ],
      ),
    ),
  };

  Widget _heading(DateTime day) {
    final ledger = widget.ledger;
    final spent = ledger.spentOn(day);
    return DayHeading(
      day,
      total: spent == 0 ? null : '支出 ${ledger.money(spent)}',
    );
  }

  Widget _tile(Entry e, {required bool last}) {
    final ledger = widget.ledger;
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
          style: TextStyle(color: Hue.onAccent, fontWeight: FontWeight.w700),
        ),
      ),
      // Taken from the book before the line goes, so a refusal leaves it
      // in place.
      confirmDismiss: (_) async => _remove(e),
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
}

/// One line of the record list.
sealed class _Item {}

/// A day's date and what was spent on it.
final class _Heading extends _Item {
  _Heading(this.day);

  final DateTime day;
}

/// The day's entries, newest first, on one card.
final class _Group extends _Item {
  _Group(this.entries);

  final List<Entry> entries;
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
    padding: const EdgeInsets.only(left: 2),
    child: Material(
      color: Hue.white,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onTap,
        icon: GlyphIcon(glyph, size: 18),
      ),
    ),
  );
}
