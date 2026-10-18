import 'package:flutter/material.dart';

import '../compose/calculator.dart';
import '../compose/pickers.dart';
import '../look/figures.dart';
import '../look/glyphs.dart';
import '../look/icons.dart';
import '../look/theme.dart';
import '../look/widgets.dart';
import '../model/ledger.dart';
import 'account_editor.dart';
import 'dialogs.dart';
import 'nav.dart';

/// 定期交易: the next item, then items due, coming up, booked and
/// paused. Booking opens the composer so the amount can change; every
/// item opens its own form under 「管理固定項目」.
class RecurringPage extends StatefulWidget {
  const RecurringPage({super.key, required this.ledger, required this.nav});

  final Ledger ledger;
  final Nav nav;

  @override
  State<RecurringPage> createState() => _RecurringPageState();
}

class _RecurringPageState extends State<RecurringPage> {
  var _manage = false;

  void _book(Recurring item) {
    widget.nav.compose(draft: widget.ledger.booking(item));
  }

  Future<void> _edit([Recurring? item]) async {
    if (!await ensureAccount(context, widget.ledger) || !mounted) return;
    await showSheet<void>(
      context,
      (_) => _RecurringEditor(ledger: widget.ledger, item: item),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ledger = widget.ledger;
    return ListenableBuilder(
      listenable: ledger,
      builder: (context, _) {
        final today = ledger.today;
        final due = ledger.due;
        final upcoming = ledger.upcoming;
        final booked = [
          for (final r in ledger.recurring)
            for (final e in ledger.confirmationsIn(r, today.year, today.month))
              (r, e),
        ];
        final active = [
          for (final r in ledger.recurring)
            if (r.active) r,
        ];
        final paused = [
          for (final r in ledger.recurring)
            if (!r.active) r,
        ];
        final next = due.isNotEmpty
            ? due.first
            : upcoming.isNotEmpty
            ? upcoming.first
            : null;
        final nextDay = next == null ? null : ledger.nextDate(next);
        var monthly = 0;
        for (final r in active) {
          if (r.income) continue;
          final times = r.datesIn(today.year, today.month).length;
          monthly += ledger.recurringWorth(r) * times;
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          children: [
            PageHeader('定期交易', onBack: widget.nav.back),
            Tile(
              hero: true,
              icon: Glyph.subscription,
              label: next == null
                  ? '下一筆'
                  : due.isEmpty
                  ? '下一筆 · ${nextDay?.month}/${nextDay?.day}'
                  : '${due.length} 筆已到期',
              value: next?.name ?? '沒有固定項目',
              size: 28,
              sub: next?.rhythm,
              trailing: next == null
                  ? null
                  : Text(
                      ledger.recurringAmount(next),
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: next.income ? Hue.positive : Hue.negative,
                      ),
                    ),
              onTap: next == null ? null : () => _book(next),
            ),
            TileRow([
              Tile(
                icon: Glyph.recurring,
                label: '本月固定支出',
                value: groupDigits(monthly),
                sub: '共 ${active.length} 項',
              ),
              Tile(
                icon: Glyph.add,
                label: '新增固定項目',
                value: '＋ 新增',
                size: 16,
                onTap: _edit,
              ),
            ]),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => setState(() => _manage = !_manage),
                icon: const GlyphIcon(Glyph.sliders, size: 18),
                label: Text(_manage ? '完成' : '管理固定項目'),
                style: TextButton.styleFrom(foregroundColor: Hue.muted),
              ),
            ),
            if (_manage)
              _Card([
                for (final r in ledger.recurring)
                  _Row(
                    ledger: ledger,
                    item: r,
                    day: ledger.nextDate(r),
                    status: r.rhythm,
                    onTap: () => _edit(r),
                  ),
              ])
            else ...[
              if (due.isNotEmpty) ...[
                _Heading('已到期', due.length),
                _Card([
                  for (final r in due)
                    _Row(
                      ledger: ledger,
                      item: r,
                      day: ledger.pendingDate(r),
                      status: '入帳',
                      onTap: () => _book(r),
                    ),
                ]),
              ],
              _Heading('即將到期', upcoming.length),
              _Card([
                for (final r in upcoming)
                  _Row(
                    ledger: ledger,
                    item: r,
                    day: ledger.pendingDate(r),
                    status: r.rhythm,
                    onTap: () => _book(r),
                  ),
              ]),
              _Heading('已入帳', booked.length),
              _Card([
                for (final (r, e) in booked)
                  _Row(
                    ledger: ledger,
                    item: r,
                    day: e.date,
                    amount: e.amount,
                    status: '已入帳',
                    onTap: () => widget.nav.showEntry(e),
                  ),
              ]),
              if (paused.isNotEmpty) ...[
                _Heading('已暫停', paused.length),
                _Card([
                  for (final r in paused)
                    _Row(
                      ledger: ledger,
                      item: r,
                      status: '已暫停',
                      onTap: () => _edit(r),
                    ),
                ]),
              ],
            ],
          ],
        );
      },
    );
  }
}

class _Card extends StatelessWidget {
  const _Card(this.rows);

  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    return SoftPanel(
      color: Hue.white,
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(children: rows),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.title, this.count);

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    return SectionHead(
      title,
      trailing: Text(
        '$count 筆',
        style: const TextStyle(fontSize: 12, color: Hue.muted),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.ledger,
    required this.item,
    required this.status,
    required this.onTap,
    this.day,
    this.amount,
  });

  final Ledger ledger;
  final Recurring item;
  final String status;
  final VoidCallback onTap;
  final DateTime? day;
  final int? amount;

  @override
  Widget build(BuildContext context) {
    final muted = !item.active;
    final date = day;
    final category = ledger.category(item.category);
    final account = ledger.account(item.account);
    final currency = account.currency;
    final booked = amount;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Hue.line)),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                padding: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  color: Hue.tile,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: date == null
                    ? IconBadge(
                        iconFor(category.icon),
                        category.color,
                        size: 30,
                      )
                    : Column(
                        children: [
                          Text(
                            '${date.month}月',
                            style: const TextStyle(
                              fontSize: 10,
                              color: Hue.muted,
                            ),
                          ),
                          Text(
                            '${date.day}',
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: muted ? Hue.muted : Hue.ink,
                      ),
                    ),
                    Text(
                      '${item.category} · ${account.name}',
                      style: const TextStyle(fontSize: 12, color: Hue.muted),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    booked == null
                        ? ledger.recurringAmount(item)
                        : amountIn(booked, currency),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: muted
                          ? Hue.muted
                          : item.income
                          ? Hue.positive
                          : Hue.negative,
                    ),
                  ),
                  Text(
                    status,
                    style: const TextStyle(fontSize: 12, color: Hue.muted),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
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
  late final _name = TextEditingController(text: widget.item?.name ?? '');
  late var _income = widget.item?.income ?? false;
  late var _amount = widget.item?.amount ?? 0;
  String? _problem;
  late var _category = widget.item?.category ?? _firstCategory(false);
  late var _account =
      widget.item?.account ?? widget.ledger.openAccounts.first.id;
  late var _unit = widget.item?.unit ?? RepeatUnit.month;
  late var _every = widget.item?.every ?? 1;
  late var _start = _firstDay();
  late DateTime? _end = widget.item?.end;
  late var _active = widget.item?.active ?? true;

  Ledger get _ledger => widget.ledger;

  String get _currency => _ledger.account(_account).currency;

  String _firstCategory(bool income) {
    final choices = widget.ledger.categoriesFor(income: income);
    return choices.isEmpty ? '' : choices.first.name;
  }

  DateTime _firstDay() {
    final item = widget.item;
    if (item == null) return widget.ledger.today;
    final start = item.start;
    if (start != null) return start;
    final today = widget.ledger.today;
    return DateTime.utc(today.year, today.month, item.day);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty || _amount <= 0) {
      setState(() => _problem = name.isEmpty ? '請輸入名稱' : '請輸入金額');
      return;
    }
    _ledger.saveRecurring(
      Recurring(
        id: widget.item?.id ?? _ledger.newId(),
        name: name,
        amount: _amount,
        day: _start.day,
        account: _account,
        category: _category,
        active: _active,
        unit: _unit,
        every: _every,
        start: _start,
        end: _end,
        income: _income,
        merchant: widget.item?.merchant ?? '',
      ),
    );
    Navigator.of(context).pop();
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
    final category = _ledger.category(_category);
    final account = _ledger.account(_account);
    final end = _end;
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
            selected: _income ? 1 : 0,
            selectedColor: _income ? Hue.positive : Hue.negative,
            onChanged: (i) => setState(() {
              _income = i == 1;
              _category = _firstCategory(_income);
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
              value: amountIn(_amount, _currency),
              valueColor: _income ? Hue.positive : Hue.negative,
              onTap: () async {
                final value = await showCalculator(
                  context,
                  title: '金額',
                  initial: _amount,
                  color: _income ? Hue.positive : Hue.negative,
                  unit: _currency,
                );
                if (value != null) setState(() => _amount = value);
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
                  selected: _category,
                  options: [
                    for (final c in _ledger.categoriesFor(income: _income))
                      Option(c.name, c.name, iconFor(c.icon), c.color),
                  ],
                );
                if (picked != null) setState(() => _category = picked);
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
                  selected: _account,
                  columns: 3,
                  options: [
                    for (final a in _ledger.openAccounts)
                      Option(
                        a.id,
                        a.name,
                        accountIcon(a),
                        accountColor(a.kind),
                      ),
                  ],
                );
                if (picked == null) return;
                setState(() {
                  // An amount in another currency means something else.
                  if (_ledger.account(picked).currency != _currency) {
                    _amount = 0;
                  }
                  _account = picked;
                });
              },
            ),
            Tile(
              icon: Glyph.calendar,
              label: '開始',
              value: '${_start.year}/${_start.month}/${_start.day}',
              size: 15,
              onTap: () async {
                final day = await _pick('開始日', _start);
                if (day != null) setState(() => _start = day);
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
                  selected: _unit.index,
                  onChanged: (i) =>
                      setState(() => _unit = RepeatUnit.values[i]),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Text('每', style: TextStyle(fontSize: 15)),
                    IconButton(
                      tooltip: '減少',
                      onPressed: _every > 1
                          ? () => setState(() => _every--)
                          : null,
                      icon: const Text('−', style: TextStyle(fontSize: 20)),
                    ),
                    Text(
                      '$_every',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    IconButton(
                      tooltip: '增加',
                      onPressed: () => setState(() => _every++),
                      icon: const Text('＋', style: TextStyle(fontSize: 18)),
                    ),
                    Text(_unit.label, style: const TextStyle(fontSize: 15)),
                    const Spacer(),
                    Text(
                      Recurring(
                        id: '',
                        name: '',
                        amount: 0,
                        day: _start.day,
                        account: '',
                        category: '',
                        unit: _unit,
                        every: _every,
                        start: _start,
                      ).rhythm,
                      style: const TextStyle(fontSize: 12, color: Hue.muted),
                    ),
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
                  : GestureDetector(
                      onTap: () => setState(() => _end = null),
                      child: const GlyphIcon(Glyph.close, size: 16),
                    ),
              onTap: () async {
                final day = await _pick('結束日', end ?? _start);
                if (day != null) setState(() => _end = day);
              },
            ),
            Tile(
              icon: Glyph.recurring,
              label: '狀態',
              value: _active ? '進行中' : '已暫停',
              size: 15,
              onTap: () => setState(() => _active = !_active),
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
