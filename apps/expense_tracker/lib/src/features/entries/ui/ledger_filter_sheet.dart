import 'package:flutter/material.dart';

import '../../../core/look/figures.dart';
import '../../../core/look/glyphs.dart';
import '../../../core/look/theme.dart';
import '../../../core/look/widgets.dart';
import '../../../core/ledger/ledger.dart';
import '../../../core/ui/pickers.dart';

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

/// What the record list is narrowed to: a kind, an account, a category,
/// a span of days in place of the month, and bounds on the amount. Each
/// is unset (null, or every kind) when it does not narrow anything.
final class LedgerFilter {
  const LedgerFilter({
    this.kind = KindFilter.all,
    this.account,
    this.category,
    this.range,
    this.least,
    this.most,
  });

  final KindFilter kind;
  final String? account;

  /// Entries of this category, its subcategories or a split part in it.
  final String? category;

  /// A span of days in place of the month; null shows the month.
  final DateTimeRange? range;

  /// The smallest and largest amount shown; null for no bound.
  final int? least;
  final int? most;

  bool get boundsAmount => least != null || most != null;

  /// How many of the filters narrow the list.
  int get count => [
    kind != KindFilter.all,
    range != null,
    boundsAmount,
    account != null,
    category != null,
  ].where((on) => on).length;

  LedgerFilter withKind(KindFilter kind) => LedgerFilter(
    kind: kind,
    account: account,
    category: category,
    range: range,
    least: least,
    most: most,
  );

  LedgerFilter withoutAccount() => LedgerFilter(
    kind: kind,
    category: category,
    range: range,
    least: least,
    most: most,
  );

  LedgerFilter withoutCategory() => LedgerFilter(
    kind: kind,
    account: account,
    range: range,
    least: least,
    most: most,
  );

  LedgerFilter withoutRange() => LedgerFilter(
    kind: kind,
    account: account,
    category: category,
    least: least,
    most: most,
  );

  LedgerFilter withoutAmounts() => LedgerFilter(
    kind: kind,
    account: account,
    category: category,
    range: range,
  );

  /// Whether [e] is shown; [ledger] knows which category is under which.
  bool shows(Ledger ledger, Entry e) {
    final range = this.range;
    final least = this.least;
    final most = this.most;
    final account = this.account;
    final category = this.category;
    if (!kind.shows(e)) return false;
    if (range != null) {
      final day = _utcDay(e.date);
      if (day.isBefore(_utcDay(range.start)) ||
          day.isAfter(_utcDay(range.end))) {
        return false;
      }
    }
    if (least != null && e.amount < least) return false;
    if (most != null && e.amount > most) return false;
    if (account != null && e.account != account && e.to != account) {
      return false;
    }
    return category == null ||
        e.category == category ||
        ledger.category(e.category).parent == category ||
        e.parts.any((p) => p.$1 == category);
  }

  static DateTime _utcDay(DateTime d) => DateTime.utc(d.year, d.month, d.day);

  /// The chosen days as words, such as 9/1–10/4.
  static String rangeLabel(DateTimeRange range) =>
      '${range.start.month}/${range.start.day}–'
      '${range.end.month}/${range.end.day}';

  /// The amount bounds as words, such as 金額 100–500.
  String get amountLabel => switch ((least, most)) {
    (final least?, final most?) =>
      '金額 ${groupDigits(least)}–${groupDigits(most)}',
    (final least?, null) => '金額 ${groupDigits(least)} 以上',
    (null, final most?) => '金額 ${groupDigits(most)} 以下',
    _ => '',
  };
}

/// Opens 篩選 over [current]; returns the filter applied, or null when
/// the sheet is closed without 套用.
Future<LedgerFilter?> showLedgerFilter(
  BuildContext context,
  Ledger ledger,
  LedgerFilter current,
) => showSheet<LedgerFilter>(
  context,
  (_) => _FilterSheet(ledger: ledger, initial: current),
);

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.ledger, required this.initial});

  final Ledger ledger;
  final LedgerFilter initial;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

/// The quick spans of 日期, counted back from today.
enum _Span {
  month('依月份', null),
  week('近 7 天', 7),
  thirty('近 30 天', 30),
  custom('自訂', null);

  const _Span(this.label, this.days);

  final String label;
  final int? days;
}

class _FilterSheetState extends State<_FilterSheet> {
  late var _kind = widget.initial.kind;
  late var _account = widget.initial.account;
  late var _category = widget.initial.category;
  late var _range = widget.initial.range;
  late final _least = TextEditingController(
    text: widget.initial.least?.toString() ?? '',
  );
  late final _most = TextEditingController(
    text: widget.initial.most?.toString() ?? '',
  );

  DateTime get _today {
    final t = widget.ledger.today;
    return DateTime(t.year, t.month, t.day);
  }

  @override
  void dispose() {
    _least.dispose();
    _most.dispose();
    super.dispose();
  }

  /// The quick span [_range] is, or 自訂 for any other days.
  _Span get _span {
    final range = _range;
    if (range == null) return _Span.month;
    final today = _today;
    for (final span in [_Span.week, _Span.thirty]) {
      final start = today.subtract(Duration(days: span.days! - 1));
      if (_sameDay(range.end, today) && _sameDay(range.start, start)) {
        return span;
      }
    }
    return _Span.custom;
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  void _pickSpan(int index) {
    final span = _Span.values[index];
    final days = span.days;
    if (span == _Span.custom) {
      _pickRange();
    } else {
      final today = _today;
      setState(
        () => _range = days == null
            ? null
            : DateTimeRange(
                start: today.subtract(Duration(days: days - 1)),
                end: today,
              ),
      );
    }
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: _today,
      initialDateRange: _range,
      helpText: '選擇日期區間',
      saveText: '確定',
    );
    if (picked != null && mounted) setState(() => _range = picked);
  }

  Future<void> _pickAccount() async {
    final picked = await pickOption<String>(
      context,
      title: '帳戶',
      selected: _account,
      columns: 3,
      options: accountOptions(widget.ledger),
    );
    if (picked != null && mounted) setState(() => _account = picked);
  }

  Future<void> _pickCategory() async {
    final ledger = widget.ledger;
    bool top(Category c) => c.parent == null;
    final picked = await pickOption<String>(
      context,
      title: '分類',
      selected: _category,
      options: [
        ...categoryOptions(ledger, income: false, where: top),
        ...categoryOptions(ledger, income: true, where: top),
      ],
    );
    if (picked != null && mounted) setState(() => _category = picked);
  }

  void _clear() {
    setState(() {
      _kind = KindFilter.all;
      _account = null;
      _category = null;
      _range = null;
      _least.clear();
      _most.clear();
    });
  }

  void _apply() {
    Navigator.of(context).pop(
      LedgerFilter(
        kind: _kind,
        account: _account,
        category: _category,
        range: _range,
        least: int.tryParse(_least.text.trim()),
        most: int.tryParse(_most.text.trim()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ledger = widget.ledger;
    final range = _range;
    final span = _span;
    final account = _account;
    final category = _category;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '篩選',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
                TextButton(
                  onPressed: _clear,
                  style: TextButton.styleFrom(foregroundColor: Hue.muted),
                  child: const Text('清除'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final (i, kind) in KindFilter.values.indexed) ...[
                  if (i > 0) const SizedBox(width: 6),
                  Expanded(
                    child: _KindTile(
                      kind: kind,
                      selected: kind == _kind,
                      onTap: () => setState(() => _kind = kind),
                    ),
                  ),
                ],
              ],
            ),
            const _Heading('日期'),
            Segments(
              labels: [
                for (final s in _Span.values)
                  s == _Span.custom && span == _Span.custom && range != null
                      ? LedgerFilter.rangeLabel(range)
                      : s.label,
              ],
              selected: span.index,
              onChanged: _pickSpan,
            ),
            const _Heading('金額'),
            Row(
              children: [
                Expanded(child: _AmountField(_least, '最少')),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  child: Text('–', style: TextStyle(color: Hue.muted)),
                ),
                Expanded(child: _AmountField(_most, '最多')),
              ],
            ),
            const SizedBox(height: 16),
            _ChoiceRow(
              label: '帳戶',
              value: account == null ? '全部' : ledger.account(account).name,
              onTap: _pickAccount,
              onClear: account == null
                  ? null
                  : () => setState(() => _account = null),
            ),
            const SizedBox(height: 8),
            _ChoiceRow(
              label: '分類',
              value: category ?? '全部',
              onTap: _pickCategory,
              onClear: category == null
                  ? null
                  : () => setState(() => _category = null),
            ),
            const SizedBox(height: 20),
            FilledButton(onPressed: _apply, child: const Text('套用')),
          ],
        ),
      ),
    );
  }
}

/// A heading over a part of the sheet.
class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 6),
    child: Text(text, style: const TextStyle(color: Hue.muted)),
  );
}

/// One kind of entry as a square: its mark over its name, filled in the
/// kind's colour when chosen.
class _KindTile extends StatelessWidget {
  const _KindTile({
    required this.kind,
    required this.selected,
    required this.onTap,
  });

  final KindFilter kind;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (glyph, color) = switch (kind) {
      KindFilter.all => (Glyph.records, Hue.accent),
      KindFilter.expense => (Glyph.payout, Hue.negative),
      KindFilter.income => (Glyph.income, Hue.positive),
      KindFilter.transfer => (Glyph.transfer, Hue.transfer),
      KindFilter.investment => (Glyph.investment, Hue.investment),
    };
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: kind.label,
      excludeSemantics: true,
      child: Material(
        color: selected ? softOf(color) : Hue.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: selected ? color : Colors.transparent,
            width: 1.5,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              children: [
                GlyphIcon(glyph, size: 20, color: selected ? color : Hue.muted),
                const SizedBox(height: 4),
                Text(
                  kind.label,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? color : Hue.ink,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 帳戶 or 分類: what is chosen, opening the choices; × goes back to all.
class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.label,
    required this.value,
    required this.onTap,
    required this.onClear,
  });

  final String label;
  final String value;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final clear = onClear;
    return Material(
      color: Hue.surface,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.only(left: 14, right: 4),
          child: Row(
            children: [
              Text(label, style: const TextStyle(color: Hue.muted)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  value,
                  textAlign: TextAlign.end,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: clear == null ? Hue.ink : Hue.accent,
                  ),
                ),
              ),
              if (clear != null)
                IconButton(
                  tooltip: '改回全部$label',
                  onPressed: clear,
                  icon: const GlyphIcon(
                    Glyph.close,
                    size: 16,
                    color: Hue.muted,
                  ),
                )
              else
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: GlyphIcon(Glyph.next, size: 16, color: Hue.muted),
                ),
            ],
          ),
        ),
      ),
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
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
    ),
  );
}
