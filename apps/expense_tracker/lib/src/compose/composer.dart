import 'package:flutter/material.dart';

import '../demo/ledger.dart';
import '../look/figures.dart';
import '../look/glyphs.dart';
import '../look/icons.dart';
import '../look/theme.dart';
import '../look/widgets.dart';
import '../pages/dialogs.dart';
import 'calculator.dart';
import 'pickers.dart';

/// The four tabs of the composer.
enum ComposeMode {
  expense('支出', Glyph.bag, Hue.negative, Hue.expenseSoft),
  income('收入', Glyph.income, Hue.positive, Hue.incomeSoft),
  transfer('轉帳', Glyph.transfer, Hue.transfer, Hue.transferSoft),
  investment('投資', Glyph.investment, Hue.investment, Hue.investmentSoft);

  const ComposeMode(this.label, this.icon, this.color, this.soft);

  final String label;
  final Glyph icon;
  final Color color;
  final Color soft;

  static ComposeMode of(EntryType type) => switch (type) {
    EntryType.expense => expense,
    EntryType.income => income,
    EntryType.transfer => transfer,
    _ => investment,
  };
}

/// A form put aside with 暫存, by tab.
final _drafts = <ComposeMode, _Draft>{};

final class _Draft {
  const _Draft(this.state);

  final Map<String, Object?> state;
}

/// Opens the composer for a new entry of [type], or to change [entry].
/// Returns the saved entry, or null when closed.
Future<Entry?> openComposer(
  BuildContext context,
  Ledger ledger, {
  EntryType type = EntryType.expense,
  Entry? entry,
}) {
  return showDialog<Entry>(
    context: context,
    builder: (_) => Dialog(
      backgroundColor: Hue.panel,
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Composer(ledger: ledger, type: entry?.type ?? type, entry: entry),
    ),
  );
}

class Composer extends StatefulWidget {
  const Composer({
    super.key,
    required this.ledger,
    required this.type,
    this.entry,
  });

  final Ledger ledger;
  final EntryType type;

  /// The entry being changed, if any.
  final Entry? entry;

  @override
  State<Composer> createState() => _ComposerState();
}

class _ComposerState extends State<Composer> {
  late ComposeMode _mode;
  late EntryType _trade;
  late int _amount;
  late DateTime _date;
  late String _account;
  late String _to;
  late String _category;
  String? _holding;
  late int _shares;
  final _note = TextEditingController();
  String? _problem;

  Ledger get _ledger => widget.ledger;

  @override
  void initState() {
    super.initState();
    final entry = widget.entry;
    _mode = ComposeMode.of(widget.type);
    _trade = widget.type.index >= EntryType.buy.index
        ? widget.type
        : EntryType.buy;
    _fresh();
    if (entry != null) {
      _amount = entry.amount;
      _date = entry.date;
      _account = entry.account;
      _to = entry.to ?? _to;
      _category = entry.category.isEmpty ? _category : entry.category;
      _holding = entry.holding;
      _shares = entry.shares;
      _note.text = entry.note;
    } else {
      final draft = _drafts[_mode];
      if (draft != null) _restore(draft);
    }
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  /// Empty fields with sensible first choices for the current tab.
  void _fresh() {
    final accounts = _ledger.accounts;
    _amount = 0;
    _date = _ledger.today;
    _account = accounts.first.id;
    _to = accounts.length > 1 ? accounts[1].id : accounts.first.id;
    final common = _commonCategories();
    final categories = _ledger.categoriesFor(
      income: _mode == ComposeMode.income,
    );
    _category = common.isNotEmpty
        ? common.first
        : categories.isEmpty
        ? ''
        : categories.first.name;
    _holding = _ledger.holdings.isEmpty ? null : _ledger.holdings.first.code;
    _shares = 0;
    _note.text = '';
    _problem = null;
  }

  /// Up to four categories of this tab, most used over the last two
  /// months first, so a new entry starts on the likely one.
  List<String> _commonCategories() {
    final income = _mode == ComposeMode.income;
    final type = income ? EntryType.income : EntryType.expense;
    final today = _ledger.today;
    final counts = <String, int>{};
    for (final back in const [0, 1]) {
      final month = DateTime.utc(today.year, today.month - back);
      for (final e in _ledger.entriesIn(month.year, month.month)) {
        if (e.type == type) counts[e.category] = (counts[e.category] ?? 0) + 1;
      }
    }
    final names = {
      for (final c in _ledger.categoriesFor(income: income)) c.name,
    };
    final ranked = counts.keys.where(names.contains).toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    return ranked.take(4).toList();
  }

  Map<String, Object?> _save() => {
    'trade': _trade,
    'amount': _amount,
    'date': _date,
    'account': _account,
    'to': _to,
    'category': _category,
    'holding': _holding,
    'shares': _shares,
    'note': _note.text,
  };

  void _restore(_Draft draft) {
    final s = draft.state;
    _trade = s['trade']! as EntryType;
    _amount = s['amount']! as int;
    _date = s['date']! as DateTime;
    _account = s['account']! as String;
    _to = s['to']! as String;
    _category = s['category']! as String;
    _holding = s['holding'] as String?;
    _shares = s['shares']! as int;
    _note.text = s['note']! as String;
  }

  void _switch(ComposeMode mode) {
    if (mode == _mode) return;
    setState(() {
      _mode = mode;
      _fresh();
      final draft = _drafts[mode];
      if (draft != null && widget.entry == null) _restore(draft);
    });
  }

  EntryType get _type => switch (_mode) {
    ComposeMode.expense => EntryType.expense,
    ComposeMode.income => EntryType.income,
    ComposeMode.transfer => EntryType.transfer,
    ComposeMode.investment => _trade,
  };

  Color get _color {
    if (_mode != ComposeMode.investment) return _mode.color;
    return _trade == EntryType.sell ? Hue.positive : Hue.investment;
  }

  String get _title {
    if (widget.entry != null) return '編輯紀錄';
    return switch (_type) {
      EntryType.expense => '新增支出',
      EntryType.income => '新增收入',
      EntryType.transfer => '帳戶轉帳',
      _ => '新增投資',
    };
  }

  String get _action {
    if (widget.entry != null) return '儲存修改';
    return switch (_type) {
      EntryType.expense => '記下支出',
      EntryType.income => '記下收入',
      EntryType.transfer => '確認轉帳',
      EntryType.buy => '記下買入',
      EntryType.sell => '記下賣出',
      EntryType.dividend => '記下股息',
    };
  }

  String get _sign => switch (_type) {
    _ when _amount == 0 => '',
    EntryType.expense || EntryType.buy => '−',
    EntryType.transfer => '',
    _ => '+',
  };

  Future<void> _calculate() async {
    final value = await showCalculator(
      context,
      title: '輸入金額',
      initial: _amount,
      color: _color,
    );
    if (value != null) setState(() => _amount = value);
  }

  Future<void> _calculateShares() async {
    final value = await showCalculator(
      context,
      title: '輸入股數',
      initial: _shares,
      color: Hue.investment,
      unit: '股',
    );
    if (value != null) setState(() => _shares = value);
  }

  Future<void> _pickDate() async {
    final marked = {
      for (final e in _ledger.entriesIn(_date.year, _date.month)) e.date,
    };
    final day = await pickDate(
      context,
      title: '入帳日期',
      selected: _date,
      latest: _ledger.today,
      marked: marked,
    );
    if (day != null) setState(() => _date = day);
  }

  Future<String?> _pickAccount(String title, String selected) {
    return pickOption<String>(
      context,
      title: title,
      selected: selected,
      columns: 3,
      options: [
        for (final a in _ledger.accounts)
          Option(a.id, a.name, accountIcon(a), accountColor(a.kind)),
      ],
    );
  }

  Future<void> _pickCategory() async {
    final income = _mode == ComposeMode.income;
    final picked = await pickOption<String>(
      context,
      title: income ? '收入分類' : '支出分類',
      selected: _category,
      options: [
        for (final c in _ledger.categoriesFor(income: income))
          Option(c.name, c.name, iconFor(c.icon), c.color),
      ],
    );
    if (picked != null) setState(() => _category = picked);
  }

  Future<void> _pickHolding() async {
    final picked = await pickOption<String>(
      context,
      title: '投資標的',
      selected: _holding,
      columns: 3,
      options: [
        for (final h in _ledger.holdings)
          Option(
            h.code,
            '${h.code} ${h.name}',
            Glyph.investment,
            Hue.investment,
          ),
      ],
    );
    if (picked != null) setState(() => _holding = picked);
  }

  Future<void> _newHolding() async {
    final code = await askText(context, '新增標的代號');
    if (code != null) setState(() => _holding = code.toUpperCase());
  }

  void _submit() {
    final type = _type;
    String? problem;
    if (_amount <= 0) {
      problem = '請輸入金額';
    } else if (type == EntryType.transfer && _account == _to) {
      problem = '轉出與轉入不能是同一個帳戶';
    } else if (_mode == ComposeMode.investment && _holding == null) {
      problem = '請選擇投資標的';
    } else if ((type == EntryType.buy || type == EntryType.sell) &&
        _shares <= 0) {
      problem = '請輸入股數';
    }
    if (problem != null) {
      setState(() => _problem = problem);
      return;
    }
    final entry = Entry(
      id: widget.entry?.id ?? _ledger.newId(),
      date: _date,
      type: type,
      amount: _amount,
      account: _account,
      category: switch (type) {
        EntryType.transfer => '轉帳',
        EntryType.dividend => '股息收入',
        EntryType.buy || EntryType.sell => '投資',
        _ => _category,
      },
      note: _note.text.trim(),
      to: type == EntryType.transfer ? _to : null,
      holding: _mode == ComposeMode.investment ? _holding : null,
      shares: type == EntryType.buy || type == EntryType.sell ? _shares : 0,
      recurring: widget.entry?.recurring,
    );
    try {
      if (widget.entry == null) {
        _ledger.add(entry);
      } else {
        _ledger.replace(entry);
      }
    } on StateError catch (error) {
      setState(() => _problem = error.message);
      return;
    }
    _drafts.remove(_mode);
    Navigator.of(context).pop(entry);
  }

  @override
  Widget build(BuildContext context) {
    final problem = _problem;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              TextButton(
                onPressed: () => setState(() {
                  _drafts.remove(_mode);
                  _fresh();
                }),
                style: TextButton.styleFrom(foregroundColor: Hue.ink),
                child: const Text('重填', style: TextStyle(fontSize: 12)),
              ),
              Expanded(
                child: Text(
                  _title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: '關閉',
                onPressed: () => Navigator.of(context).pop(),
                icon: const GlyphIcon(Glyph.close, size: 20, color: Hue.muted),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (final mode in ComposeMode.values)
                Expanded(child: _tab(mode)),
            ],
          ),
          if (_mode == ComposeMode.investment) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                for (final (trade, label) in const [
                  (EntryType.buy, '買入'),
                  (EntryType.sell, '賣出'),
                  (EntryType.dividend, '股息'),
                ])
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Material(
                        color: trade == _trade
                            ? Hue.investmentSoft
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => setState(() => _trade = trade),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Text(
                              label,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontWeight: trade == _trade
                                    ? FontWeight.w700
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          InkWell(
            onTap: _calculate,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
              child: Row(
                children: [
                  const Text(
                    'TWD',
                    style: TextStyle(fontSize: 12, color: Hue.muted),
                  ),
                  Expanded(
                    child: Text(
                      '$_sign${groupDigits(_amount)}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w500,
                        color: _color,
                      ),
                    ),
                  ),
                  const GlyphIcon(Glyph.calculator, color: Hue.muted),
                ],
              ),
            ),
          ),
          TextButton.icon(
            onPressed: _pickDate,
            icon: const GlyphIcon(Glyph.calendar, size: 16),
            label: Text(fullDay(_date)),
            style: TextButton.styleFrom(foregroundColor: Hue.muted),
          ),
          const SizedBox(height: 8),
          ..._fields(),
          const SizedBox(height: 14),
          TextField(
            controller: _note,
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(
              hintText: '備註',
              prefixIcon: const Padding(
                padding: EdgeInsets.only(bottom: 22),
                child: GlyphIcon(Glyph.note, size: 18),
              ),
              filled: true,
              fillColor: Hue.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          if (problem != null)
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
              TextButton(
                onPressed: widget.entry != null
                    ? () => Navigator.of(context).pop()
                    : () {
                        _drafts[_mode] = _Draft(_save());
                        Navigator.of(context).pop();
                      },
                style: TextButton.styleFrom(
                  foregroundColor: Hue.muted,
                  minimumSize: const Size(64, 46),
                ),
                child: Text(widget.entry != null ? '取消' : '暫存'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 46,
                  child: FilledButton(
                    onPressed: _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: _color,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(_action),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tab(ComposeMode mode) {
    final picked = mode == _mode;
    final locked = widget.entry != null && !picked;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Material(
        color: picked ? mode.soft : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: locked ? null : () => _switch(mode),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GlyphIcon(
                  mode.icon,
                  size: 16,
                  color: picked ? mode.color : Hue.muted,
                ),
                const SizedBox(width: 4),
                Text(
                  mode.label,
                  style: TextStyle(
                    fontSize: 14,
                    color: picked ? mode.color : Hue.muted,
                    fontWeight: picked ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _fields() {
    final account = _ledger.account(_account);
    final accountField = _Field(
      label: switch (_type) {
        EntryType.expense || EntryType.buy => '付款帳戶',
        EntryType.transfer => '轉出',
        _ => '收款帳戶',
      },
      icon: accountIcon(account),
      color: accountColor(account.kind),
      value: account.name,
      onTap: () async {
        final picked = await _pickAccount('選擇帳戶', _account);
        if (picked != null) setState(() => _account = picked);
      },
    );
    switch (_mode) {
      case ComposeMode.expense || ComposeMode.income:
        final category = _ledger.category(_category);
        return [
          Row(
            children: [
              Expanded(child: accountField),
              Expanded(
                child: _Field(
                  label: _mode == ComposeMode.income ? '收入分類' : '支出分類',
                  icon: iconFor(category.icon),
                  color: category.color,
                  value: category.name,
                  onTap: _pickCategory,
                ),
              ),
            ],
          ),
        ];
      case ComposeMode.transfer:
        final to = _ledger.account(_to);
        return [
          Row(
            children: [
              Expanded(child: accountField),
              Container(
                width: 30,
                height: 30,
                margin: const EdgeInsets.only(top: 18),
                decoration: const BoxDecoration(
                  color: Hue.transfer,
                  shape: BoxShape.circle,
                ),
                child: const GlyphIcon(Glyph.arrow, size: 18, color: Hue.white),
              ),
              Expanded(
                child: _Field(
                  label: '轉入',
                  icon: accountIcon(to),
                  color: accountColor(to.kind),
                  value: to.name,
                  onTap: () async {
                    final picked = await _pickAccount('轉入帳戶', _to);
                    if (picked != null) setState(() => _to = picked);
                  },
                ),
              ),
            ],
          ),
        ];
      case ComposeMode.investment:
        final code = _holding;
        final held = code == null ? null : _ledger.holding(code);
        return [
          Row(
            children: [
              Expanded(
                child: SoftPanel(
                  color: Hue.investmentSoft,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  onTap: _pickHolding,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '投資標的',
                        style: TextStyle(fontSize: 12, color: Hue.muted),
                      ),
                      Text(
                        code == null ? '選擇標的' : '$code ${held?.name ?? ''}',
                        style: const TextStyle(fontSize: 15),
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                tooltip: '新增標的',
                onPressed: _newHolding,
                icon: const GlyphIcon(Glyph.add, color: Hue.investment),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: accountField),
              if (_trade != EntryType.dividend)
                Expanded(
                  child: InkWell(
                    onTap: _calculateShares,
                    child: Column(
                      children: [
                        const Text(
                          '股數',
                          style: TextStyle(fontSize: 13, color: Hue.muted),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              groupDigits(_shares),
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const Text(' 股'),
                            const SizedBox(width: 6),
                            const GlyphIcon(
                              Glyph.calculator,
                              size: 18,
                              color: Hue.muted,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ];
    }
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.icon,
    required this.color,
    required this.value,
    required this.onTap,
  });

  final String label;
  final Glyph icon;
  final Color color;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          children: [
            Text(label, style: const TextStyle(fontSize: 13, color: Hue.muted)),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconBadge(icon, color, size: 30),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
