import 'package:flutter/material.dart';

import '../../../core/look/dialogs.dart';
import '../../../core/text/figures.dart';
import '../../../core/look/glyphs.dart';
import '../../../core/ui/icons.dart';
import '../../../core/look/theme.dart';
import '../../../core/look/widgets.dart';
import '../../../core/ledger/ledger.dart';
import '../../../core/ui/calculator.dart';
import '../../../core/ui/pickers.dart';
import '../model/recurring_schedule.dart';
import '../model/recurring_form.dart';

part 'recurring_repeat.dart';

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
    _ledger.recurringCommands.removeRecurring(item.id);
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
    final color = shownColor(Color(category.color));
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
                      style: const TextStyle(
                        fontSize: TextSize.tiny,
                        color: Hue.muted,
                      ),
                    ),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: TextSize.body,
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
                                fontSize: TextSize.title,
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
                          fontSize: TextSize.heading,
                          fontWeight: FontWeight.w800,
                          color: ink,
                        ),
                        decoration: InputDecoration.collapsed(
                          hintText: '點這裡取個名字',
                          hintStyle: TextStyle(
                            fontSize: TextSize.heading,
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
                            fontSize: TextSize.heading,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        TextSpan(
                          text: amountIn(_f.amount, _f.currency),
                          style: const TextStyle(
                            fontSize: TextSize.hero,
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
                    ? SquareIcon(
                        iconFor(c.icon),
                        shownColor(Color(c.color)),
                        size: 48,
                      )
                    : Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: tintOf(shownColor(Color(c.color)), 0.22),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        alignment: Alignment.center,
                        child: GlyphIcon(
                          iconFor(c.icon),
                          size: 22,
                          color: shownColor(Color(c.color)),
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
                      child: GlyphIcon(
                        Glyph.check,
                        size: 11,
                        color: shownColor(Color(c.color)),
                      ),
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
                fontSize: TextSize.caption,
                fontWeight: chosen ? FontWeight.w800 : FontWeight.w400,
                color: chosen ? deepOf(shownColor(Color(c.color))) : Hue.muted,
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
