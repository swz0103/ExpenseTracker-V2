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

  static const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

  static String _date(DateTime d) => '${d.year}/${d.month}/${d.day}';

  /// A choice inside the repeat card: a small button as wide as its
  /// words, with a mark that it opens a list.
  Widget _chip(String text, String label, VoidCallback onTap) => TapArea(
    label: label,
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.fromLTRB(12, 9, 6, 9),
      decoration: BoxDecoration(
        color: Hue.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const Icon(Icons.expand_more, size: 18, color: Hue.muted),
        ],
      ),
    ),
  );

  Future<void> _pickEvery() async {
    final picked = await pickOption<int>(
      context,
      title: '每幾${_f.unit.label}',
      selected: _f.every,
      columns: 4,
      options: [
        for (var n = 1; n <= 12; n++)
          Option(n, '$n', Glyph.recurring, Hue.accent),
      ],
    );
    if (picked != null) setState(() => _f.every = picked);
  }

  Future<void> _pickDayOfMonth() async {
    final picked = await pickOption<int>(
      context,
      title: '每月幾日',
      selected: _f.start.day,
      columns: 7,
      options: [
        for (var d = 1; d <= 31; d++)
          Option(d, '$d', Glyph.calendar, Hue.accent),
      ],
    );
    if (picked != null) setState(() => _f.setDayOfMonth(picked));
  }

  Future<void> _pickWeekday() async {
    final picked = await pickOption<int>(
      context,
      title: '星期幾',
      selected: _f.start.weekday,
      columns: 4,
      options: [
        for (var w = 1; w <= 7; w++)
          Option(w, '週${_weekdays[w - 1]}', Glyph.calendar, Hue.accent),
      ],
    );
    if (picked != null) setState(() => _f.setWeekday(picked));
  }

  /// The anchor of the rhythm: the day of the month, the weekday, or the
  /// date in the year; a daily item has none.
  Widget? _anchor() => switch (_f.unit) {
    RepeatUnit.day => null,
    RepeatUnit.week => _chip(
      '週${_weekdays[_f.start.weekday - 1]}',
      '星期幾',
      _pickWeekday,
    ),
    RepeatUnit.month => _chip('${_f.start.day} 日', '每月幾日', _pickDayOfMonth),
    RepeatUnit.year => _chip(
      '${_f.start.month}/${_f.start.day}',
      '每年哪一天',
      () async {
        final day = await _pick('每年哪一天', _f.start);
        if (day != null) setState(() => _f.start = day);
      },
    ),
  };

  /// 重複: how often, said once at the top; the unit; every how many and
  /// on which day; then when it starts and ends, and whether it is paused.
  Widget _repeatCard() {
    final end = _f.end;
    final anchor = _anchor();
    Widget line(String label, Widget value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(label, style: const TextStyle(fontSize: 14.5)),
          const Spacer(),
          value,
        ],
      ),
    );
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 8),
      decoration: BoxDecoration(
        color: Hue.tile,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const GlyphIcon(Glyph.recurring, size: 18, color: Hue.accent),
              const SizedBox(width: 8),
              const Text(
                '重複',
                style: TextStyle(fontSize: 13, color: Hue.muted),
              ),
              const Spacer(),
              Text(
                _f.active ? _f.rhythm : '${_f.rhythm}（已暫停）',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Segments(
            labels: const ['天', '週', '月', '年'],
            selected: _f.unit.index,
            onChanged: (i) => setState(() => _f.unit = RepeatUnit.values[i]),
          ),
          const SizedBox(height: 10),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              const Text('每', style: TextStyle(fontSize: 15)),
              _chip('${_f.every}', '每幾${_f.unit.label}', _pickEvery),
              Text(
                anchor == null ? _f.unit.label : '${_f.unit.label}，',
                style: const TextStyle(fontSize: 15),
              ),
              ?anchor,
            ],
          ),
          const Divider(height: 20),
          line(
            '開始',
            _chip(_date(_f.start), '開始日', () async {
              final day = await _pick('開始日', _f.start);
              if (day != null) setState(() => _f.start = day);
            }),
          ),
          line(
            '結束',
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (end != null)
                  TapArea(
                    label: '不結束',
                    onTap: () => setState(() => _f.end = null),
                    child: const GlyphIcon(Glyph.close, size: 16),
                  ),
                _chip(end == null ? '不結束' : _date(end), '結束日', () async {
                  final day = await _pick('結束日', end ?? _f.start);
                  if (day != null) setState(() => _f.end = day);
                }),
              ],
            ),
          ),
          line(
            '暫停',
            Switch(
              value: !_f.active,
              onChanged: (paused) => setState(() => _f.active = !paused),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final category = _ledger.category(_f.category);
    final account = _ledger.account(_f.account);
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
          ]),
          _repeatCard(),
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
