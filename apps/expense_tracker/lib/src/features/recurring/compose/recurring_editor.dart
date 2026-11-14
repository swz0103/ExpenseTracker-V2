import 'package:flutter/material.dart';

import '../../../core/look/dialogs.dart';
import '../../../core/look/figures.dart';
import '../../../core/look/glyphs.dart';
import '../../../core/look/icons.dart';
import '../../../core/look/theme.dart';
import '../../../core/look/widgets.dart';
import '../../../core/ledger/ledger.dart';
import '../../../core/ui/calculator.dart';
import '../../../core/ui/pickers.dart';
import '../model/calendar.dart';
import '../model/recurring_form.dart';

/// Opens the form of a recurring item as a bottom sheet: a new one
/// (starting [on] that day, when given), or [item] to change. Saving
/// writes to [ledger] directly.
Future<void> editRecurring(
  BuildContext context,
  Ledger ledger, {
  Recurring? item,
  DateTime? on,
}) {
  return showSheet<void>(
    context,
    (_) => _RecurringEditor(ledger: ledger, item: item, on: on),
  );
}

/// The form of a recurring item, where the card is the form: 支出 or
/// 收入 on two big buttons; a card in its category's colour with the
/// name, the amount (the calculator beside), the account and how often;
/// the usual categories under it; a strip with what differs from the
/// defaults (when it starts, booked by itself, an end, paused); and the
/// save button in the side's colour.
class _RecurringEditor extends StatefulWidget {
  const _RecurringEditor({required this.ledger, this.item, this.on});

  final Ledger ledger;
  final Recurring? item;
  final DateTime? on;

  @override
  State<_RecurringEditor> createState() => _RecurringEditorState();
}

class _RecurringEditorState extends State<_RecurringEditor> {
  /// The fields and what saving does.
  late final _f = RecurringForm(widget.ledger, old: widget.item, on: widget.on);
  late final TextEditingController _name = TextEditingController(text: _f.name)
    ..addListener(() => _f.name = _name.text);
  String? _problem;

  Ledger get _ledger => widget.ledger;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    if (_f.save()) {
      Navigator.of(context).pop();
    } else {
      setState(() => _problem = _f.problem);
    }
  }

  Future<void> _remove() async {
    final item = widget.item;
    if (item == null) return;
    final ok = await confirm(
      context,
      '刪除「${item.name}」？',
      '刪除',
      danger: true,
      body: '已記的紀錄會保留。',
    );
    if (!ok || !mounted) return;
    _ledger.removeRecurring(item.id);
    Navigator.of(context).pop();
  }

  Future<void> _amount() async {
    final value = await showCalculator(
      context,
      title: '金額',
      initial: _f.amount,
      color: _f.income ? Hue.positive : Hue.negative,
    );
    if (value != null) setState(() => _f.amount = value);
  }

  Future<void> _account() async {
    final picked = await pickAccount(
      context,
      _ledger,
      title: _f.income ? '存入哪個帳戶' : '從哪個帳戶扣',
      selected: _f.account,
    );
    if (picked != null) setState(() => _f.setAccount(picked));
  }

  Future<void> _allCategories() async {
    final picked = await pickOption<String>(
      context,
      title: '分類',
      selected: _f.category,
      options: categoryOptions(_ledger, income: _f.income),
    );
    if (picked != null) setState(() => _f.category = picked);
  }

  Future<void> _repeat() async {
    await showSheet<void>(context, (_) => _RepeatSheet(form: _f));
    if (mounted) setState(() {});
  }

  Future<void> _others() async {
    await showSheet<void>(
      context,
      (_) => _OtherSheet(form: _f, ledger: _ledger),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final category = _ledger.category(_f.category);
    final color = category.color;
    final ink = deepOf(color);
    final side = _f.income ? Hue.positive : Hue.negative;
    final editing = widget.item != null;
    final usual = usualCategories(_ledger, income: _f.income);
    if (!usual.any((c) => c.name == _f.category) &&
        _f.category.isNotEmpty &&
        usual.isNotEmpty) {
      usual
        ..removeLast()
        ..insert(0, category);
    }
    final start = _f.start;
    final notes = [
      '${start.month}/${start.day} 起',
      _f.auto ? '到期自動入帳' : '手動入帳',
      if (_f.end case final end?) '到 ${end.month}/${end.day}',
      if (!_f.active) '已暫停',
    ];
    Widget mini(String label, String value, VoidCallback onTap) => Material(
      color: Hue.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(fontSize: 11.5, color: Hue.muted),
                    ),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const GlyphIcon(Glyph.next, size: 14, color: Hue.muted),
            ],
          ),
        ),
      ),
    );
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              for (final (i, income) in const [false, true].indexed) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(
                  child: Semantics(
                    selected: _f.income == income,
                    child: Material(
                      color: _f.income == income
                          ? (income ? Hue.positive : Hue.negative)
                          : Hue.surface,
                      borderRadius: BorderRadius.circular(16),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => setState(() => _f.setIncome(income)),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 50),
                          child: Center(
                            child: Text(
                              income ? '收入' : '支出',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: _f.income == income
                                    ? Hue.onAccent
                                    : Hue.muted,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          // The card is the form.
          Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 12, 14),
            decoration: BoxDecoration(
              color: tintOf(color, 0.22),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    SquareIcon(iconFor(category.icon), color, size: 48),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _name,
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                          color: ink,
                        ),
                        decoration: InputDecoration.collapsed(
                          hintText: '點這裡取個名字',
                          hintStyle: TextStyle(
                            fontSize: 18,
                            color: ink.withValues(alpha: 0.55),
                          ),
                        ),
                      ),
                    ),
                    if (editing)
                      Material(
                        color: Hue.white,
                        borderRadius: BorderRadius.circular(14),
                        child: IconButton(
                          tooltip: '刪除',
                          onPressed: _remove,
                          icon: const GlyphIcon(
                            Glyph.trash,
                            size: 18,
                            color: Hue.danger,
                          ),
                        ),
                      )
                    else
                      GlyphIcon(Glyph.edit, size: 16, color: ink),
                  ],
                ),
                const SizedBox(height: 10),
                AmountTap(
                  label: '金額 ${_f.amount}',
                  onTap: _amount,
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text:
                              '${_f.currency == homeCode ? 'NT\$' : _f.currency} ',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        TextSpan(
                          text: amountIn(_f.amount, _f.currency),
                          style: const TextStyle(
                            fontSize: 44,
                            fontWeight: FontWeight.w800,
                            color: Hue.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: mini(
                          _f.income ? '存入' : '帳戶',
                          _ledger.account(_f.account).name,
                          _account,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: mini('重複', _f.rhythm, _repeat)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_problem case final problem?)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(problem, style: const TextStyle(color: Hue.danger)),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final c in usual) ...[
                Expanded(child: _categoryChoice(c)),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Semantics(
                  button: true,
                  label: '全部分類',
                  child: InkWell(
                    onTap: _allCategories,
                    borderRadius: BorderRadius.circular(16),
                    child: Column(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: Hue.surface,
                            borderRadius: BorderRadius.circular(15),
                          ),
                          alignment: Alignment.center,
                          child: const GlyphIcon(
                            Glyph.grid,
                            size: 22,
                            color: Hue.muted,
                          ),
                        ),
                        const SizedBox(height: 18),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ColorCard(
            color: Hue.faint,
            amount: 0.18,
            radius: 16,
            onTap: _others,
            label: '其他設定',
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                const GlyphIcon(Glyph.calendar, size: 18, color: Hue.muted),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    notes.join(' · '),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                const GlyphIcon(Glyph.next, size: 14, color: Hue.muted),
              ],
            ),
          ),
          const SizedBox(height: 14),
          PanelButton(
            editing
                ? '儲存'
                : _f.income
                ? '儲存固定收入'
                : '儲存固定支出',
            color: editing ? Hue.accent : side,
            onTap: _save,
          ),
        ],
      ),
    );
  }

  Widget _categoryChoice(Category c) {
    final chosen = c.name == _f.category;
    return Semantics(
      button: true,
      selected: chosen,
      label: c.name,
      excludeSemantics: true,
      child: InkWell(
        onTap: () => setState(() => _f.category = c.name),
        borderRadius: BorderRadius.circular(16),
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                chosen
                    ? SquareIcon(iconFor(c.icon), c.color, size: 48)
                    : Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: tintOf(c.color, 0.22),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        alignment: Alignment.center,
                        child: GlyphIcon(
                          iconFor(c.icon),
                          size: 22,
                          color: c.color,
                        ),
                      ),
                if (chosen)
                  Positioned(
                    right: -4,
                    top: -4,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: const BoxDecoration(
                        color: Hue.white,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: GlyphIcon(Glyph.check, size: 11, color: c.color),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              c.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: chosen ? FontWeight.w800 : FontWeight.w400,
                color: chosen ? deepOf(c.color) : Hue.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 多久一次: 每天, 每週, 每月 or 每年; then the day: a grid of dates for a
/// month, seven weekdays for a week, the twelve months and a date for a
/// year, how many days for every few days; every how many; and the next
/// three times.
class _RepeatSheet extends StatefulWidget {
  const _RepeatSheet({required this.form});

  final RecurringForm form;

  @override
  State<_RepeatSheet> createState() => _RepeatSheetState();
}

class _RepeatSheetState extends State<_RepeatSheet> {
  RecurringForm get _f => widget.form;

  Widget _cell(String label, bool chosen, VoidCallback onTap) => Semantics(
    button: true,
    selected: chosen,
    child: Material(
      color: chosen ? Hue.accent : Hue.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(onTap),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: chosen ? Hue.onAccent : Hue.ink,
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _days() => CardGrid(columns: 7, gap: 6, [
    for (var d = 1; d <= 31; d++)
      _cell('$d', _f.start.day == d, () => _f.setDayOfMonth(d)),
  ]);

  void _setMonth(int month) {
    final start = _f.start;
    var day = DateTime.utc(start.year, month, start.day);
    if (day.month != month) day = DateTime.utc(start.year, month + 1, 0);
    if (day.isBefore(DateTime.utc(start.year, start.month, start.day))) {
      day = DateTime.utc(day.year + 1, day.month, day.day);
    }
    _f.start = day;
  }

  @override
  Widget build(BuildContext context) {
    const units = [
      (RepeatUnit.day, '每天'),
      (RepeatUnit.week, '每週'),
      (RepeatUnit.month, '每月'),
      (RepeatUnit.year, '每年'),
    ];
    final next = nextTimes(_f.build(), _f.start);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(
            child: Text(
              '多久一次',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final (i, (unit, label)) in units.indexed) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(
                  child: _cell(label, _f.unit == unit, () => _f.unit = unit),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          switch (_f.unit) {
            RepeatUnit.month => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('每個月的哪一天', style: mutedSmall),
                const SizedBox(height: 8),
                _days(),
              ],
            ),
            RepeatUnit.week => Row(
              children: [
                for (var w = 1; w <= 7; w++) ...[
                  if (w > 1) const SizedBox(width: 6),
                  Expanded(
                    child: _cell(
                      weekdayNames[w - 1],
                      _f.start.weekday == w,
                      () => _f.setWeekday(w),
                    ),
                  ),
                ],
              ],
            ),
            RepeatUnit.year => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('哪個月', style: mutedSmall),
                const SizedBox(height: 8),
                CardGrid(columns: 6, gap: 6, [
                  for (var m = 1; m <= 12; m++)
                    _cell('$m', _f.start.month == m, () => _setMonth(m)),
                ]),
                const SizedBox(height: 12),
                const Text('哪一天', style: mutedSmall),
                const SizedBox(height: 8),
                CardGrid(columns: 7, gap: 6, [
                  for (var d = 1; d <= 31; d++)
                    _cell('$d', _f.start.day == d, () {
                      final s = _f.start;
                      final day = DateTime.utc(s.year, s.month, d);
                      if (day.month == s.month) _f.start = day;
                    }),
                ]),
              ],
            ),
            RepeatUnit.day => const SizedBox(),
          },
          const SizedBox(height: 14),
          Row(
            children: [
              const Text('每', style: TextStyle(fontSize: 16)),
              IconButton(
                tooltip: '少一',
                onPressed: _f.every > 1
                    ? () => setState(() => _f.step(-1))
                    : null,
                icon: const Text(
                  '−',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                '${_f.every}',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              IconButton(
                tooltip: '多一',
                onPressed: () => setState(() => _f.step(1)),
                icon: const GlyphIcon(Glyph.add, size: 20),
              ),
              Text(_f.unit.label, style: const TextStyle(fontSize: 16)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '接下來：${next.map((d) => '${d.month}/${d.day}').join('、')}',
            textAlign: TextAlign.center,
            style: mutedSmall,
          ),
          const SizedBox(height: 12),
          PanelButton(
            '完成',
            color: Hue.accent,
            onTap: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

/// 其他設定: when it starts and ends, whether it books itself when due,
/// and whether it is paused.
class _OtherSheet extends StatefulWidget {
  const _OtherSheet({required this.form, required this.ledger});

  final RecurringForm form;
  final Ledger ledger;

  @override
  State<_OtherSheet> createState() => _OtherSheetState();
}

class _OtherSheetState extends State<_OtherSheet> {
  RecurringForm get _f => widget.form;

  Future<DateTime?> _pick(String title, DateTime selected) => pickDate(
    context,
    title: title,
    selected: selected,
    latest: DateTime.utc(widget.ledger.today.year + 5),
  );

  Widget _date(
    String label,
    String value,
    VoidCallback onTap, {
    VoidCallback? onClear,
  }) => ColorCard(
    color: Hue.faint,
    amount: 0.18,
    radius: 16,
    onTap: onTap,
    label: '$label $value',
    padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: mutedSmall),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        if (onClear != null)
          IconButton(
            tooltip: '不結束',
            onPressed: onClear,
            icon: const GlyphIcon(Glyph.close, size: 16, color: Hue.muted),
          ),
      ],
    ),
  );

  Widget _toggle(
    String title,
    String detail,
    bool value,
    ValueChanged<bool> set,
  ) => ColorCard(
    color: Hue.faint,
    amount: 0.18,
    radius: 16,
    onTap: () => setState(() => set(!value)),
    padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(detail, style: mutedSmall),
            ],
          ),
        ),
        TickSwitch(
          value: value,
          label: title,
          onChanged: (v) => setState(() => set(v)),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final start = _f.start;
    final end = _f.end;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(
            child: Text(
              '其他設定',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 12),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _date('開始', '${start.month}/${start.day}', () async {
                    final day = await _pick('開始日', start);
                    if (day != null) setState(() => _f.start = day);
                  }),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _date(
                    '結束',
                    end == null ? '不結束' : '${end.month}/${end.day}',
                    () async {
                      final day = await _pick('結束日', end ?? start);
                      if (day != null) setState(() => _f.end = day);
                    },
                    onClear: end == null
                        ? null
                        : () => setState(() => _f.end = null),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _toggle(
                    '到期自動入帳',
                    '到期就自動記一筆',
                    _f.auto,
                    (v) => _f.auto = v,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _toggle(
                    '暫停',
                    '先不出現在月曆',
                    !_f.active,
                    (v) => _f.active = !v,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          PanelButton(
            '完成',
            color: Hue.accent,
            onTap: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}
