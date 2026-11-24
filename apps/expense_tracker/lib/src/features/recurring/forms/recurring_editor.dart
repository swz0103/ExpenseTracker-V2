import 'package:flutter/material.dart';

import '../../../core/design_system/dialogs.dart';
import '../../../../design_system/display/amount.dart';
import '../../../core/design_system/glyphs.dart';
import '../../../core/widgets/icons.dart';
import '../../../core/design_system/theme.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/ledger/ledger.dart';
import '../../../core/widgets/calculator.dart';
import '../../../core/widgets/pickers.dart';
import '../model/recurring_schedule.dart';
import '../model/recurring_form.dart';
import 'recurring_form_widgets.dart';
import '../../../../design_system/display/date.dart';
import '../../../core/messages/recurring_messages.dart';
import '../../../core/design_system/shape.dart';
import '../../../core/design_system/spacing.dart';
import '../../../core/formatting/words.dart';

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

  /// Something was chosen or typed since the form opened (D83): leaving
  /// then asks first. Every choice the form takes rebuilds it.
  var _touched = false;

  /// The name as the form opened.
  late final String _openedName;

  @override
  void initState() {
    super.initState();
    _openedName = _f.name;
  }

  @override
  void setState(VoidCallback change) {
    _touched = true;
    super.setState(change);
  }

  Ledger get _ledger => widget.ledger;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    if (_f.save()) {
      EditGuard.close(context);
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
      Words.delete,
      danger: true,
      body: '已記的紀錄會保留。',
    );
    if (!ok || !mounted) return;
    _ledger.recurringCommands.removeRecurring(item.id);
    EditGuard.close(context);
  }

  Future<void> _amount() async {
    final value = await showCalculator(
      context,
      title: Words.amount,
      initial: _f.amount,
      color: _f.income ? AppColors.positive : AppColors.negative,
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
      title: Words.category,
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
      (_) => _OtherSheet(form: _f, today: _ledger.today),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.item != null;
    return ListenableBuilder(
      listenable: _name,
      builder: (context, form) => EditGuard(
        changed: _touched || _name.text != _openedName,
        child: form!,
      ),
      child: _form(editing),
    );
  }

  Widget _form(bool editing) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Space.s4, 0, Space.s4, Space.s4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SideChoice(
            income: _f.income,
            onChanged: (income) => setState(() => _f.setIncome(income)),
          ),
          const SizedBox(height: Space.s3),
          _card(editing: editing),
          if (_problem case final problem?)
            Padding(
              padding: const EdgeInsets.only(top: Space.s2),
              child: Text(problem, style: dangerText),
            ),
          const SizedBox(height: Space.s3),
          CategoryChoiceRow(
            choices: _f.categoryChoices,
            chosen: _f.category,
            onChosen: (name) => setState(() => _f.category = name),
            onAll: _allCategories,
          ),
          const SizedBox(height: Space.s2),
          OtherSettingsStrip(notes: _f.notes, onTap: _others),
          const SizedBox(height: Space.s4),
          Row(
            children: [
              const Expanded(child: CancelButton()),
              const SizedBox(width: Space.s2),
              Expanded(
                flex: 2,
                child: PanelButton(
                  editing
                      ? '儲存'
                      : _f.income
                      ? '儲存固定收入'
                      : '儲存固定支出',
                  color: editing
                      ? AppColors.accent
                      : (_f.income ? AppColors.positive : AppColors.negative),
                  onTap: _save,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// The card that is the form, in its category's colour: the name, the
  /// amount, and the account and how often.
  Widget _card({required bool editing}) {
    final category = _ledger.category(_f.category);
    final color = shownColor(Color(category.color));
    return Container(
      padding: const EdgeInsets.fromLTRB(
        Space.s4,
        Space.s4,
        Space.s3,
        Space.s4,
      ),
      decoration: BoxDecoration(
        color: tintOf(color, 0.22),
        borderRadius: BorderRadius.circular(Radii.largeIncreased),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _nameRow(category, color, editing: editing),
          const SizedBox(height: Space.s2),
          AmountTap(
            label: '金額 ${_f.amount}',
            onTap: _amount,
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${currencyLabel(_f.currency)} ',
                    style: const TextStyle(
                      fontSize: TextSize.heading,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  TextSpan(
                    text: figuresIn(_f.amount, _f.currency),
                    style: const TextStyle(
                      fontSize: TextSize.hero,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: Space.s2),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: FormFieldTile(
                    label: _f.income ? '存入' : Words.account,
                    value: _ledger.account(_f.account).name,
                    onTap: _account,
                  ),
                ),
                const SizedBox(width: Space.s2),
                Expanded(
                  child: FormFieldTile(
                    label: '重複',
                    value: _f.rhythm,
                    onTap: _repeat,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The category's icon, the name typed in, and 刪除 while editing.
  Widget _nameRow(Category category, Color color, {required bool editing}) {
    final ink = deepOf(color);
    return Row(
      children: [
        SquareIcon(iconFor(category.icon), color, size: 48),
        const SizedBox(width: Space.s3),
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
            color: AppColors.white,
            borderRadius: BorderRadius.circular(Radii.large),
            child: IconButton(
              tooltip: Words.delete,
              onPressed: _remove,
              icon: const GlyphIcon(
                Glyph.trash,
                size: 18,
                color: AppColors.danger,
              ),
            ),
          )
        else
          GlyphIcon(Glyph.edit, size: 16, color: ink),
      ],
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
