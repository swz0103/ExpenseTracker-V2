import 'package:flutter/material.dart';

import '../look/figures.dart';
import '../look/theme.dart';
import '../look/widgets.dart';
import '../model/ledger.dart';

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

  @override
  void dispose() {
    _least.dispose();
    _most.dispose();
    super.dispose();
  }

  Future<void> _pickRange() async {
    final today = widget.ledger.today;
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(today.year, today.month, today.day),
      initialDateRange: _range,
      helpText: '選擇日期區間',
      saveText: '確定',
    );
    if (picked != null && mounted) setState(() => _range = picked);
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
    const heading = TextStyle(color: Hue.muted);
    return SafeArea(
      top: false,
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
            const Text('類型', style: heading),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 0,
              children: [
                for (final option in KindFilter.values)
                  ChoicePill(
                    label: option.label,
                    selected: option == _kind,
                    onTap: () => setState(() => _kind = option),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            const Text('日期', style: heading),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 0,
              children: [
                ChoicePill(
                  label: '依月份',
                  selected: range == null,
                  onTap: () => setState(() => _range = null),
                ),
                ChoicePill(
                  label: range == null
                      ? '自訂區間'
                      : LedgerFilter.rangeLabel(range),
                  selected: range != null,
                  onTap: () => _pickRange(),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Text('金額', style: heading),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(child: _AmountField(_least, '最少')),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  child: Text('–', style: heading),
                ),
                Expanded(child: _AmountField(_most, '最多')),
              ],
            ),
            const SizedBox(height: 14),
            const Text('帳戶', style: heading),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 0,
              children: [
                ChoicePill(
                  label: '全部帳戶',
                  selected: _account == null,
                  onTap: () => setState(() => _account = null),
                ),
                for (final a in ledger.accounts)
                  ChoicePill(
                    label: a.name,
                    selected: _account == a.id,
                    onTap: () => setState(() => _account = a.id),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            const Text('分類', style: heading),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 0,
              children: [
                ChoicePill(
                  label: '全部分類',
                  selected: _category == null,
                  onTap: () => setState(() => _category = null),
                ),
                for (final c in ledger.categories)
                  if (!c.archived && c.parent == null)
                    ChoicePill(
                      label: c.name,
                      selected: _category == c.name,
                      onTap: () => setState(() => _category = c.name),
                    ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(onPressed: _apply, child: const Text('套用')),
            ),
          ],
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
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    ),
  );
}
