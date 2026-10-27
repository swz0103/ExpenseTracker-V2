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
import '../model/recurring_form.dart';

/// Opens the form of a recurring item as a bottom sheet: a new one, or
/// [item] to change. Saving writes to [ledger] directly.
Future<void> editRecurring(
  BuildContext context,
  Ledger ledger, {
  Recurring? item,
}) {
  return showSheet<void>(
    context,
    (_) => _RecurringEditor(ledger: ledger, item: item),
  );
}

/// The form of a recurring item: what, how much, from which account,
/// how often, from when and until when.
class _RecurringEditor extends StatefulWidget {
  const _RecurringEditor({required this.ledger, this.item});

  final Ledger ledger;
  final Recurring? item;

  @override
  State<_RecurringEditor> createState() => _RecurringEditorState();
}

class _RecurringEditorState extends State<_RecurringEditor> {
  /// The fields and what saving does.
  late final _f = RecurringForm(widget.ledger, old: widget.item);
  late final _name = TextEditingController(text: _f.name)
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
    final ok = await confirm(context, '刪除「${item.name}」？', '刪除', danger: true);
    if (!ok || !mounted) return;
    _ledger.removeRecurring(item.id);
    Navigator.of(context).pop();
  }

  Future<DateTime?> _pick(String title, DateTime selected) => pickDate(
    context,
    title: title,
    selected: selected,
    latest: DateTime.utc(_ledger.today.year + 5),
  );

  @override
  Widget build(BuildContext context) {
    final category = _ledger.category(_f.category);
    final account = _ledger.account(_f.account);
    final end = _f.end;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.item == null ? '新增固定項目' : '編輯固定項目',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Segments(
            labels: const ['支出', '收入'],
            selected: _f.income ? 1 : 0,
            selectedColor: _f.income ? Hue.positive : Hue.negative,
            onChanged: (i) => setState(() {
              _f.setIncome(i == 1);
            }),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _name,
            decoration: InputDecoration(
              hintText: '名稱',
              filled: true,
              fillColor: Hue.tile,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          TileRow([
            Tile(
              icon: Glyph.calculator,
              label: '金額',
              value: amountIn(_f.amount, _f.currency),
              valueColor: _f.income ? Hue.positive : Hue.negative,
              onTap: () async {
                final value = await showCalculator(
                  context,
                  title: '金額',
                  initial: _f.amount,
                  color: _f.income ? Hue.positive : Hue.negative,
                  unit: _f.currency,
                );
                if (value != null) setState(() => _f.amount = value);
              },
            ),
            Tile(
              icon: iconFor(category.icon),
              label: '分類',
              value: category.name,
              size: 15,
              onTap: () async {
                final picked = await pickOption<String>(
                  context,
                  title: '分類',
                  selected: _f.category,
                  options: categoryOptions(_ledger, income: _f.income),
                );
                if (picked != null) setState(() => _f.category = picked);
              },
            ),
          ]),
          TileRow([
            Tile(
              icon: accountIcon(account),
              label: '帳戶',
              value: account.name,
              size: 15,
              onTap: () async {
                final picked = await pickOption<String>(
                  context,
                  title: '帳戶',
                  selected: _f.account,
                  columns: 3,
                  options: accountOptions(_ledger),
                );
                if (picked == null) return;
                setState(() {
                  _f.setAccount(picked);
                });
              },
            ),
            Tile(
              icon: Glyph.calendar,
              label: '開始',
              value: '${_f.start.year}/${_f.start.month}/${_f.start.day}',
              size: 15,
              onTap: () async {
                final day = await _pick('開始日', _f.start);
                if (day != null) setState(() => _f.start = day);
              },
            ),
          ]),
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
            decoration: BoxDecoration(
              color: Hue.tile,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Segments(
                  labels: const ['每天', '每週', '每月', '每年'],
                  selected: _f.unit.index,
                  onChanged: (i) =>
                      setState(() => _f.unit = RepeatUnit.values[i]),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Text('每', style: TextStyle(fontSize: 15)),
                    IconButton(
                      tooltip: '減少',
                      onPressed: _f.every > 1
                          ? () => setState(() => _f.step(-1))
                          : null,
                      icon: const Text('−', style: TextStyle(fontSize: 20)),
                    ),
                    Text(
                      '${_f.every}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    IconButton(
                      tooltip: '增加',
                      onPressed: () => setState(() => _f.step(1)),
                      icon: const Text('＋', style: TextStyle(fontSize: 18)),
                    ),
                    Text(_f.unit.label, style: const TextStyle(fontSize: 15)),
                    const Spacer(),
                    Text(_f.rhythm, style: mutedSmall),
                  ],
                ),
              ],
            ),
          ),
          TileRow([
            Tile(
              icon: Glyph.calendar,
              label: '結束',
              value: end == null
                  ? '不結束'
                  : '${end.year}/${end.month}/${end.day}',
              size: 15,
              trailing: end == null
                  ? null
                  : TapArea(
                      label: '不結束',
                      onTap: () => setState(() => _f.end = null),
                      child: const GlyphIcon(Glyph.close, size: 16),
                    ),
              onTap: () async {
                final day = await _pick('結束日', end ?? _f.start);
                if (day != null) setState(() => _f.end = day);
              },
            ),
            Tile(
              icon: Glyph.recurring,
              label: '狀態',
              value: _f.active ? '進行中' : '已暫停',
              size: 15,
              onTap: () => setState(() => _f.active = !_f.active),
            ),
          ]),
          if (_problem case final problem?)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                problem,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Hue.danger),
              ),
            ),
          const SizedBox(height: 14),
          Row(
            children: [
              if (widget.item != null)
                TextButton(
                  onPressed: _remove,
                  style: TextButton.styleFrom(
                    foregroundColor: Hue.danger,
                    minimumSize: const Size(64, 46),
                  ),
                  child: const Text('刪除'),
                ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: Hue.accent,
                    minimumSize: const Size.fromHeight(46),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('儲存'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
