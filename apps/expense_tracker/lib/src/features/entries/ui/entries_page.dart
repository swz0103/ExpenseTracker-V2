import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../design_system/display/amount.dart';
import '../../../core/widgets/pickers.dart';
import '../../../core/design_system/glyphs.dart';
import '../../../core/design_system/haptics.dart';
import '../../../core/design_system/theme.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/ledger/ledger.dart';
import '../../../core/widgets/entry_tile.dart';
import 'entries_filter_sheet.dart';
import 'entries_search.dart';
import '../../../core/navigation/nav.dart';
import '../../../core/widgets/balance_hero.dart';
import '../../../core/widgets/shown_amounts.dart';
import '../../../core/design_system/shape.dart';
import '../../../core/design_system/spacing.dart';
import '../../../core/formatting/words.dart';
import '../../../core/messages/flow_messages.dart';

import 'package:core/time/utc_days.dart';
import 'package:core/time/month_arithmetic.dart';

/// 收支紀錄: the month's income against spending, then every entry by
/// day, with search and filters; 設定 exports it.
class EntriesPage extends StatefulWidget {
  const EntriesPage({super.key, required this.ledger, required this.nav});

  final Ledger ledger;
  final Nav nav;

  @override
  State<EntriesPage> createState() => _EntriesPageState();
}

class _EntriesPageState extends State<EntriesPage> {
  late var _month = (widget.ledger.today.year, widget.ledger.today.month);
  var _filter = const EntryFilter();

  /// The words searched for, once typing has paused.
  String? _search;

  /// Waits for a pause in typing before searching, so each letter does
  /// not go through every entry.
  Timer? _typing;

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

  void _clearSearch() {
    _typing?.cancel();
    _searchText.clear();
    _searchFocus.unfocus();
    setState(() => _search = null);
  }

  void _toggle(Entry e) {
    Haptics.selection();
    setState(() {
      if (!_picked.remove(e.id)) _picked.add(e.id);
    });
  }

  /// The picked entries still in the ledger, each looked up by its id.
  List<Entry> get _pickedEntries => [
    for (final id in _picked) ?widget.ledger.entries.byId(id),
  ];

  /// Says how many of the picked entries a change reached, and ends the
  /// picking.
  void _done(String what, int changed) {
    final total = _picked.length;
    setState(_picked.clear);
    showNote(
      context,
      changed == total
          ? '已$what ${countOf(changed, CountUnit.entries)}'
          : '已$what ${countOf(changed, CountUnit.entries)}，其餘 ${countOf(total - changed, CountUnit.entries)}不適用',
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
    _done('改分類', ledger.entryCommands.recategorize(picked, name));
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
    _done('改帳戶', ledger.entryCommands.moveToAccount(picked, id));
  }

  /// Deletes every picked entry as one change, with one way back for all
  /// of them. When the ledger refuses (a later sale would be short of
  /// shares) nothing is taken, the ledger says why, and the picks stay.
  void _removePicked() {
    final picked = _pickedEntries;
    if (picked.isEmpty) {
      setState(_picked.clear);
      return;
    }
    if (deleteEntries(context, widget.ledger, picked).isEmpty) return;
    setState(_picked.clear);
  }

  /// What the list shows, kept until the month, the filter, the search,
  /// the day or what it rests on changes: a frame after 隱藏金額 or a
  /// change elsewhere in the book builds only the lines on screen.
  _Shown? _kept;

  /// What the page rests on: the entries, and the accounts and categories
  /// their lines name.
  static const _topics = {Topic.entries, Topic.accounts, Topic.categories};

  late final _changes = widget.ledger.watch(_topics);

  _Shown _shownNow() {
    final ledger = widget.ledger;
    final key = (
      _month,
      _filter,
      _words,
      ledger.today,
      ledger.revisionOf(Topic.entries),
      ledger.revisionOf(Topic.accounts),
      ledger.revisionOf(Topic.categories),
    );
    final kept = _kept;
    if (kept != null && kept.key == key) return kept;
    final shown = _shown();
    return _kept = _Shown(key, shown, ledger.reportService.totalsOf(shown));
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
      source = ledger.entryQueryService.search(words);
    } else if (range != null) {
      source = [
        for (final m in monthStarts(
          range.start,
          monthStart(range.end),
        ).toList().reversed)
          // Exception to as-of-today: the list shows 預定 entries marked; its
          // totals go through countedOn.
          ...ledger.entries.inMonth(m.year, m.month),
      ];
    } else {
      // Exception to as-of-today: the list shows 預定 entries marked; its totals
      // go through countedOn.
      source = ledger.entries.inMonth(year, month);
    }
    return [
      // Entries written as one are shown as one, by the spending.
      for (final e in source)
        if (filter.shows(ledger, e) && !ledger.entryQueryService.isGroupTail(e))
          e,
    ];
  }

  Future<void> _openFilter() async {
    final applied = await showLedgerFilter(context, widget.ledger, _filter);
    if (applied != null && mounted) setState(() => _filter = applied);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _changes,
      builder: (context, _) {
        final shown = _shownNow();
        final lines = shown.lines;
        // The title and month stay on top; the rest scrolls under them.
        final [title, ...head] = _head(shown);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.s5),
              child: title,
            ),
            Expanded(
              // A swipe across the page goes to the month before or after;
              // a row's own slide, to 編輯 and 刪除, still wins on the row.
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragEnd: (details) {
                  final speed = details.primaryVelocity ?? 0;
                  if (speed.abs() < 300) return;
                  _stepMonth(speed < 0 ? 1 : -1);
                },
                // One line per heading and per entry: only the lines on
                // screen are built, however many a day holds.
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(
                    Space.s5,
                    0,
                    Space.s5,
                    Space.s4,
                  ),
                  itemCount: head.length + lines.length,
                  itemBuilder: (context, i) =>
                      i < head.length ? head[i] : _line(lines[i - head.length]),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Moves [by] months, never past this one.
  void _stepMonth(int by) {
    final today = widget.ledger.today;
    final (year, month) = shiftMonth(_month.$1, _month.$2, by);
    if (monthIndex(year, month) > monthIndex(today.year, today.month)) return;
    Haptics.selection();
    setState(() => _month = (year, month));
  }

  /// The search box's look: a white pill with a magnifier, and a clear
  /// button once something is typed.
  InputDecoration _searchDecoration() => InputDecoration(
    hintText: '搜尋備註、商家、標籤、金額',
    isDense: true,
    filled: true,
    fillColor: AppColors.white,
    contentPadding: const EdgeInsets.symmetric(vertical: Space.s4),
    prefixIcon: const Padding(
      padding: EdgeInsets.all(Space.s3),
      child: GlyphIcon(Glyph.search, size: 18, color: AppColors.muted),
    ),
    suffixIcon: _searchText.text.isEmpty
        ? null
        : IconButton(
            tooltip: '清除搜尋',
            onPressed: _clearSearch,
            icon: const GlyphIcon(
              Glyph.close,
              size: 16,
              color: AppColors.muted,
            ),
          ),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(Radii.large),
      borderSide: BorderSide.none,
    ),
  );

  /// What sits above the entries: the title and month, the month's sums
  /// or what to do with the picked entries, search and the filters on.
  List<Widget> _head(_Shown shown) {
    final ledger = widget.ledger;
    final (_, month) = _month;
    final filter = _filter;
    final words = _words;
    final searching = words.isNotEmpty;
    final account = filter.account;
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
              ? '搜尋「$words」'
              : switch (filter.range) {
                  final range? => '${EntryFilter.rangeLabel(range)} 結餘',
                  null => '$month 月結餘',
                },
          income: shown.income,
          expense: shown.expense,
          rate: false,
          size: 28,
        ),
      const SizedBox(height: Space.s2),
      EntriesSearchRow(
        text: _searchText,
        focus: _searchFocus,
        decoration: _searchDecoration,
        onChanged: _typed,
        filterCount: filter.count,
        onFilter: _openFilter,
      ),
      if (filter.count > 0)
        EntriesFilterPills(
          filter: filter,
          accountName: account == null ? null : ledger.account(account).name,
          onChange: (change) => setState(() => _filter = change(_filter)),
        ),
      if (shown.lines.isEmpty) _empty(searching || filter.count > 0),
    ];
  }

  /// Nothing to list: none written yet, or none this month in a book
  /// that has others (D117), with 記一筆; or none the search and filters
  /// let through, with 清除篩選 (D85).
  Widget _empty(bool narrowed) => narrowed
      ? EmptyState(
          glyph: Glyph.search,
          color: AppColors.accent,
          message: FlowWords.noMatches,
          action: FlowWords.clearFilters,
          actionKey: Keys.emptyAction('entries'),
          onAction: _clearAll,
        )
      : EmptyState(
          glyph: Glyph.records,
          color: AppColors.accent,
          message: widget.ledger.entries.isEmpty
              ? FlowWords.noEntriesYet
              : FlowWords.noEntriesThisMonth,
          action: FlowWords.addEntry,
          actionKey: Keys.emptyAction('entries'),
          onAction: () => unawaited(widget.nav.compose()),
        );

  /// Takes the search and every filter away.
  void _clearAll() {
    _clearSearch();
    setState(() => _filter = const EntryFilter());
  }

  /// A line of the list: a day's heading with what was spent, or one of
  /// the day's entries, a slice of the day's card.
  Widget _line(_Line line) => switch (line) {
    _Heading(:final day) => _heading(day),
    _Row(:final entry, :final first, :final last) => GroupBox(
      // None: a row's 編輯 and 刪除 reach the card's edges.
      padding: EdgeInsets.zero,
      top: first,
      bottom: last,
      child: _tile(entry, last: last),
    ),
  };

  Widget _heading(DateTime day) {
    final ledger = widget.ledger;
    final spent = ledger.reportService.spentOn(day);
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
            ? AppColors.accent.withValues(alpha: 0.12)
            : null,
        child: EntryTile(
          ledger: ledger,
          entry: e,
          divider: !last,
          merge: true,
          onTap: () => _toggle(e),
        ),
      );
    }
    return EntryRow(
      ledger: ledger,
      entry: e,
      divider: !last,
      merge: true,
      onOpen: widget.nav.showEntry,
      onLongPress: () => _toggle(e),
    );
  }
}

/// What the record list shows for one month, filter, search and day,
/// with the [key] they make: the entries, as lines, and their sums.
final class _Shown {
  _Shown(this.key, List<Entry> shown, ({int income, int expense}) totals)
    : lines = _linesOf(shown),
      income = totals.income,
      expense = totals.expense;

  final Record key;
  final List<_Line> lines;
  final int income;
  final int expense;

  /// Each day's heading, then its entries, newest first, one line each.
  static List<_Line> _linesOf(List<Entry> shown) => [
    for (final (i, e) in shown.indexed) ...[
      if (i == 0 || shown[i - 1].date != e.date) _Heading(e.date),
      _Row(
        e,
        first: i == 0 || shown[i - 1].date != e.date,
        last: i == shown.length - 1 || shown[i + 1].date != e.date,
      ),
    ],
  ];
}

/// One line of the record list.
sealed class _Line {}

/// A day's date and what was spent on it.
final class _Heading extends _Line {
  _Heading(this.day);

  final DateTime day;
}

/// One of a day's entries: a slice of the day's card, the [first] with
/// its top corners and the [last] with its bottom ones.
final class _Row extends _Line {
  _Row(this.entry, {required this.first, required this.last});

  final Entry entry;
  final bool first;
  final bool last;
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
    Widget action(String label, VoidCallback onTap, {Color? color, Key? key}) =>
        TextButton(
          key: key,
          onPressed: onTap,
          style: wordButton(color ?? AppColors.accent),
          child: Text(label),
        );
    return GroupBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '已選 ${countOf(count, CountUnit.entries)} · 點紀錄可加選或取消',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                tooltip: Words.cancel,
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
              action(
                Words.delete,
                onRemove,
                color: AppColors.danger,
                key: Keys.deletePicked,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
