import 'package:flutter/material.dart';

import '../look/figures.dart';
import '../look/glyphs.dart';
import '../look/icons.dart';
import '../look/theme.dart';
import '../look/widgets.dart';
import '../model/ledger.dart';
import '../model/trading.dart';
import '../pages/categories_page.dart';
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
final _drafts = <ComposeMode, Map<String, Object?>>{};

/// How the composer was left, when not just closed.
enum ComposeOutcome { saved, deleted, refund }

/// Opens the composer as a bottom sheet for a new entry of [type] (filled
/// in from [draft] if given), to show and change [entry], or to refund
/// [refundOf]. Returns what happened and the entry, or null when closed.
Future<(ComposeOutcome, Entry)?> openComposer(
  BuildContext context,
  Ledger ledger, {
  EntryType type = EntryType.expense,
  Entry? entry,
  Entry? draft,
  Entry? refundOf,
}) {
  return showSheet<(ComposeOutcome, Entry)>(
    context,
    (_) => Composer(
      ledger: ledger,
      type: entry?.type ?? draft?.type ?? type,
      entry: entry,
      draft: draft,
      refundOf: refundOf ?? _original(ledger, entry),
    ),
  );
}

/// The spending a refund gives back, when [entry] is one.
Entry? _original(Ledger ledger, Entry? entry) {
  final id = entry?.refundOf;
  return id == null ? null : ledger.byId(id);
}

class Composer extends StatefulWidget {
  const Composer({
    super.key,
    required this.ledger,
    required this.type,
    this.entry,
    this.draft,
    this.refundOf,
  });

  final Ledger ledger;
  final EntryType type;

  /// The entry being changed, if any.
  final Entry? entry;

  /// A new entry's starting values, such as a card payment.
  final Entry? draft;

  /// The spending being refunded, for a refund.
  final Entry? refundOf;

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
  var _price = 0.0;
  var _merchant = '';
  var _tags = <String>[];

  /// The parts of a split, or null when the whole goes to [_category].
  List<(String, int)>? _parts;
  var _fee = 0;

  /// What a foreign amount is worth in NT$, and what a transfer between
  /// currencies delivers, as typed; null works them out at today's rate.
  int? _home;
  int? _received;
  var _installments = 0;
  var _average = false;
  var _splitShares = false;
  final _note = TextEditingController();
  String? _problem;

  /// An entry opened from a list is shown first; 編輯 unlocks it.
  late var _viewing = widget.entry != null;

  Ledger get _ledger => widget.ledger;

  Entry? get _refunded => widget.refundOf;

  @override
  void initState() {
    super.initState();
    _mode = ComposeMode.of(widget.type);
    _trade = widget.type.index >= EntryType.buy.index
        ? widget.type
        : EntryType.buy;
    _fresh();
    final source = widget.entry ?? widget.draft;
    final refunded = _refunded;
    if (source != null) {
      _load(source);
    } else if (refunded != null) {
      _mode = ComposeMode.income;
      _amount = _ledger.refundable(refunded);
      _account = refunded.account;
      _category = refunded.category;
    } else {
      final draft = _drafts[_mode];
      if (draft != null) _restore(draft);
    }
  }

  void _load(Entry entry) {
    _amount = entry.amount;
    _date = entry.date;
    _account = entry.account;
    _to = entry.to ?? _to;
    _category = entry.category.isEmpty ? _category : entry.category;
    _holding = entry.holding ?? _holding;
    _shares = entry.shares;
    _price = entry.shares == 0 ? 0 : entry.amount / entry.shares;
    _note.text = entry.note;
    _merchant = entry.merchant;
    _tags = [...entry.tags];
    _parts = entry.parts.isEmpty ? null : [...entry.parts];
    _fee = entry.type == EntryType.transfer ? entry.fee : 0;
    _home = entry.home;
    _received = entry.received;
    _installments = entry.installments;
    _average = entry.average;
    _splitShares = entry.split;
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  /// Empty fields with sensible first choices for the current tab.
  void _fresh() {
    final accounts = _ledger.openAccounts;
    _amount = 0;
    _date = _ledger.today;
    _account = accounts.first.id;
    _to = accounts.length > 1 ? accounts[1].id : accounts.first.id;
    final common = _categoryChoices();
    _category = common.isEmpty ? '' : common.first;
    _holding = _ledger.holdings.isEmpty ? null : _ledger.holdings.first.code;
    _shares = 0;
    _price = 0;
    _note.text = '';
    _merchant = '';
    _tags = [];
    _parts = null;
    _fee = 0;
    _home = null;
    _received = null;
    _installments = 0;
    _average = false;
    _splitShares = false;
    _problem = null;
  }

  /// Categories of this tab, the most used over the last two months
  /// first, so a new entry starts on the likely one.
  List<String> _categoryChoices() {
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
    final names = [
      for (final c in _ledger.categoriesFor(income: income)) c.name,
    ];
    return names..sort((a, b) => (counts[b] ?? 0).compareTo(counts[a] ?? 0));
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
    'merchant': _merchant,
    'tags': _tags,
    'parts': _parts,
    'fee': _fee,
  };

  void _restore(Map<String, Object?> s) {
    _trade = s['trade']! as EntryType;
    _amount = s['amount']! as int;
    _date = s['date']! as DateTime;
    _account = s['account']! as String;
    _to = s['to']! as String;
    _category = s['category']! as String;
    _holding = s['holding'] as String?;
    _shares = s['shares']! as int;
    _note.text = s['note']! as String;
    _merchant = s['merchant']! as String;
    _tags = [...s['tags']! as List<String>];
    final parts = s['parts'] as List<(String, int)>?;
    _parts = parts == null ? null : [...parts];
    _fee = s['fee']! as int;
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
    if (_refunded != null) return Hue.positive;
    if (_mode != ComposeMode.investment) return _mode.color;
    return _trade == EntryType.sell ? Hue.positive : Hue.investment;
  }

  String get _title {
    if (_refunded != null) return widget.entry == null ? '退款' : '退款詳情';
    if (widget.entry != null) return _viewing ? '紀錄詳情' : '編輯紀錄';
    return switch (_type) {
      EntryType.expense => '新增支出',
      EntryType.income => '新增收入',
      EntryType.transfer => '帳戶轉帳',
      _ => '新增投資',
    };
  }

  String get _action {
    if (widget.entry != null) return '儲存修改';
    if (_refunded != null) return '記下退款';
    return switch (_type) {
      EntryType.expense => '記下支出',
      EntryType.income => '記下收入',
      EntryType.transfer => '確認轉帳',
      EntryType.buy => '記下買進',
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

  /// A buy or sale, whose amount comes from shares and price.
  bool get _trading =>
      _mode == ComposeMode.investment && _trade != EntryType.dividend;

  bool get _onCard =>
      _type == EntryType.expense &&
      _ledger.account(_account).kind == AccountKind.card;

  /// The currency of the account paying or receiving, and of a
  /// transfer's receiving account.
  String get _currency => _ledger.account(_account).currency;
  String get _toCurrency => _ledger.account(_to).currency;

  /// Spending or income in a foreign-currency account, which also needs
  /// its worth in NT$.
  bool get _foreign =>
      _currency != 'TWD' &&
      (_type == EntryType.expense || _type == EntryType.income);

  /// A transfer between accounts kept in different currencies.
  bool get _crossing => _type == EntryType.transfer && _currency != _toCurrency;

  /// [_home], else the refunded share of the purchase's worth, else the
  /// amount at today's rate; null without a rate.
  int? get _homeValue {
    final typed = _home;
    if (typed != null) return typed;
    final refunded = _refunded;
    final worth = refunded?.home;
    if (refunded != null && worth != null && refunded.amount > 0) {
      return (worth * _amount / refunded.amount).round();
    }
    return _ledger.toHome(_amount, _currency);
  }

  /// [_received], else the amount at today's rates.
  int? get _receivedValue =>
      _received ?? _ledger.convert(_amount, _currency, _toCurrency);

  /// The broker's fee and the tax on the trade being written.
  (int, int) get _charges {
    if (_type != EntryType.buy && _type != EntryType.sell) return (0, 0);
    final fee = brokerFee(_amount, _shares);
    final code = _holding ?? '';
    final tax = _type == EntryType.sell
        ? saleTax(code, _amount, _shares, _date)
        : 0;
    return (fee, tax);
  }

  Future<int?> _ask(String title, int initial, {String unit = 'TWD'}) {
    return showCalculator(
      context,
      title: title,
      initial: initial,
      color: _color,
      unit: unit,
    );
  }

  Future<void> _calculate() async {
    final value = await _ask('輸入金額', _amount, unit: _currency);
    if (value == null) return;
    setState(() {
      _amount = value;
      _home = null;
      _received = null;
    });
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
        for (final a in _ledger.openAccounts)
          Option(a.id, a.name, accountIcon(a), accountColor(a.kind)),
      ],
    );
  }

  Future<String?> _pickCategory(String? selected) {
    final income = _mode == ComposeMode.income;
    return pickOption<String>(
      context,
      title: income ? '收入分類' : '支出分類',
      selected: selected,
      options: [
        for (final c in _ledger.categoriesFor(income: income))
          Option(c.name, c.name, iconFor(c.icon), c.color),
      ],
    );
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

  Future<void> _pickMerchant() async {
    final picked = await showChildPage<String>(
      context,
      title: '商家',
      builder: (_) =>
          _MerchantPicker(known: _ledger.merchants, initial: _merchant),
    );
    if (picked == null) return;
    setState(() {
      _merchant = picked;
      final usual = _ledger.categoryAt(picked);
      if (usual != null && _parts == null && widget.entry == null) {
        _category = usual;
      }
    });
  }

  Future<void> _pickTags() async {
    final picked = await showChildPage<List<String>>(
      context,
      title: '標籤',
      builder: (_) => _TagPicker(known: _ledger.tags, initial: _tags),
    );
    if (picked != null) setState(() => _tags = picked);
  }

  Future<void> _pickInstallments() async {
    final picked = await pickOption<int>(
      context,
      title: '分期付款',
      selected: _installments,
      columns: 3,
      options: [
        for (final n in const [0, 3, 6, 12, 24, 30])
          Option(n, n == 0 ? '不分期' : '$n 期', Glyph.card, Hue.card),
      ],
    );
    if (picked != null) setState(() => _installments = picked);
  }

  Future<void> _newCategory() async {
    final income = _mode == ComposeMode.income;
    final count = _ledger.categories.length;
    final made = await showCategoryEditor(
      context,
      title: income ? '新增收入分類' : '新增支出分類',
      initial: Category(
        '',
        income ? 'income' : 'other',
        Hue.shades[count % Hue.shades.length],
        income: income,
      ),
      colors: Hue.shades,
    );
    if (made == null) return;
    _ledger.addCategory(made);
    setState(() => _category = made.name);
  }

  void _split() {
    setState(() {
      _parts = _parts == null ? [(_category, _amount)] : null;
    });
  }

  void _evenly() {
    final parts = _parts;
    if (parts == null || parts.isEmpty) return;
    final each = _amount ~/ parts.length;
    setState(() {
      _parts = [
        for (final (i, (name, _)) in parts.indexed)
          (
            name,
            i == parts.length - 1 ? _amount - each * (parts.length - 1) : each,
          ),
      ];
    });
  }

  Future<void> _addPart() async {
    final name = await _pickCategory(null);
    if (name == null) return;
    final parts = _parts ?? [];
    final used = parts.fold(0, (sum, p) => sum + p.$2);
    setState(() => _parts = [...parts, (name, _amount - used)]);
  }

  Future<void> _editPart(int index) async {
    final parts = _parts;
    if (parts == null) return;
    final (name, value) = parts[index];
    final amount = await _ask(name, value);
    if (amount == null) return;
    setState(() {
      _parts = [
        for (final (i, p) in parts.indexed)
          if (i != index) p else if (amount > 0) (name, amount),
      ];
    });
  }

  /// Moving between a trade and a dividend starts the shares afresh: a
  /// dividend's are the ones it adds.
  void _changeTrade(EntryType trade) {
    setState(() {
      if ((trade == EntryType.dividend) != (_trade == EntryType.dividend)) {
        _shares = 0;
        _amount = 0;
        _splitShares = false;
      }
      _trade = trade;
    });
  }

  void _submit() {
    final type = _type;
    final parts = _type == EntryType.expense && !_foreign ? _parts : null;
    final refunded = _refunded;
    final (fee, tax) = _charges;
    String? problem;
    final splitTotal = parts?.fold(0, (sum, p) => sum + p.$2);
    final stock = type == EntryType.dividend && _shares > 0;
    if (_amount <= 0 && !stock) {
      problem = _trading ? '請輸入股數和成交價' : '請輸入金額';
    } else if (type == EntryType.transfer && _account == _to) {
      problem = '轉出與轉入不能是同一個帳戶';
    } else if (_foreign && _homeValue == null) {
      problem = '還沒有匯率，請輸入折合台幣的金額';
    } else if (_crossing && _receivedValue == null) {
      problem = '還沒有匯率，請輸入轉入金額';
    } else if (type == EntryType.transfer &&
        _currency != 'TWD' &&
        _ledger.account(_to).kind == AccountKind.card) {
      problem = '外幣帳戶不能直接繳卡費';
    } else if (_mode == ComposeMode.investment && _currency != 'TWD') {
      problem = '投資請用新台幣帳戶';
    } else if (_mode == ComposeMode.investment && _holding == null) {
      problem = '請選擇投資標的';
    } else if ((type == EntryType.buy || type == EntryType.sell) &&
        _shares <= 0) {
      problem = '請輸入股數';
    } else if (splitTotal != null && splitTotal != _amount) {
      problem = '拆分的金額要等於總額（差 ${groupDigits(_amount - splitTotal)}）';
    } else if (refunded != null &&
        _amount > _ledger.refundable(refunded) + (widget.entry?.amount ?? 0)) {
      problem = '超過可退金額 ${groupDigits(_ledger.refundable(refunded))}';
    }
    if (problem != null) {
      setState(() => _problem = problem);
      return;
    }
    // A transfer's fee counts as NT$ spending: only an NT$ account pays one.
    final transferFee = _currency == 'TWD' ? _fee : 0;
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
        _ => parts == null || parts.isEmpty ? _category : parts.first.$1,
      },
      note: _note.text.trim(),
      to: type == EntryType.transfer ? _to : null,
      holding: _mode == ComposeMode.investment ? _holding : null,
      shares: _mode == ComposeMode.investment ? _shares : 0,
      recurring: widget.entry?.recurring ?? widget.draft?.recurring,
      merchant: type == EntryType.expense ? _merchant : '',
      tags: type == EntryType.expense || type == EntryType.income ? _tags : [],
      parts: parts != null && parts.length > 1 ? parts : const [],
      fee: type == EntryType.transfer ? transferFee : fee,
      tax: tax,
      refundOf: refunded?.id,
      installments: _onCard ? _installments : 0,
      average: type == EntryType.sell && _average,
      split: stock && _splitShares,
      home: _foreign ? _homeValue : null,
      received: _crossing ? _receivedValue : null,
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
    Navigator.of(context).pop((ComposeOutcome.saved, entry));
  }

  void _putAside() {
    _drafts[_mode] = _save();
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final entry = widget.entry;
    if (entry == null) return;
    final ok = await confirm(context, '刪除這一筆？', '刪除', danger: true);
    if (ok && mounted) {
      Navigator.of(context).pop((ComposeOutcome.deleted, entry));
    }
  }

  @override
  Widget build(BuildContext context) {
    final problem = _problem;
    final entry = widget.entry;
    final refunded = _refunded;
    final most = refunded == null
        ? 0
        : _ledger.refundable(refunded) + (entry?.amount ?? 0);
    final canRefund =
        _viewing &&
        entry != null &&
        entry.type == EntryType.expense &&
        _ledger.refundable(entry) > 0;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Visibility.maintain(
                visible: !_viewing && entry == null,
                child: TextButton(
                  onPressed: () => setState(() {
                    _drafts.remove(_mode);
                    _fresh();
                  }),
                  style: TextButton.styleFrom(foregroundColor: Hue.ink),
                  child: const Text('重填', style: TextStyle(fontSize: 12)),
                ),
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
          if (refunded != null)
            _OriginalTile(ledger: _ledger, entry: refunded)
          else if (_viewing)
            Center(child: Pill(_mode.label, color: _mode.color))
          else if (entry == null)
            Segments(
              labels: [for (final m in ComposeMode.values) m.label],
              selected: _mode.index,
              selectedColor: _mode.color,
              onChanged: (i) => _switch(ComposeMode.values[i]),
            ),
          if (_mode == ComposeMode.investment && refunded == null) ...[
            const SizedBox(height: 8),
            _TradeChips(
              trade: _trade,
              locked: _viewing,
              onChanged: _changeTrade,
            ),
          ],
          const SizedBox(height: 8),
          IgnorePointer(
            ignoring: _viewing,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Tile(
                  hero: true,
                  icon: Glyph.calculator,
                  label: switch (_type) {
                    _ when refunded != null => '退款金額',
                    EntryType.transfer => '轉出金額',
                    EntryType.buy || EntryType.sell => '成交金額',
                    _ => '金額',
                  },
                  value: '$_sign${amountIn(_amount, _currency)}',
                  valueColor: _color,
                  size: 34,
                  sub: refunded == null
                      ? null
                      : '最多可退 ${amountIn(most, _currency)}',
                  onTap: _trading ? null : _calculate,
                ),
                ..._fields(),
              ],
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
                onPressed: entry != null ? _delete : _putAside,
                style: TextButton.styleFrom(
                  foregroundColor: entry != null ? Hue.danger : Hue.muted,
                  minimumSize: const Size(64, 46),
                ),
                child: Text(entry != null ? '刪除' : '暫存'),
              ),
              if (canRefund)
                TextButton(
                  onPressed: () =>
                      Navigator.of(context).pop((ComposeOutcome.refund, entry)),
                  style: TextButton.styleFrom(
                    foregroundColor: Hue.positive,
                    minimumSize: const Size(64, 46),
                  ),
                  child: const Text('退款'),
                ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 46,
                  child: FilledButton(
                    onPressed: _viewing
                        ? () => setState(() => _viewing = false)
                        : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: _viewing ? Hue.accent : _color,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(_viewing ? '編輯' : _action),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _accountTile(String label) {
    final account = _ledger.account(_account);
    return Tile(
      icon: accountIcon(account),
      label: label,
      value: account.name,
      size: 15,
      onTap: () async {
        final picked = await _pickAccount('選擇帳戶', _account);
        if (picked == null) return;
        setState(() {
          _account = picked;
          _home = null;
        });
      },
    );
  }

  /// The worth in NT$ of a foreign amount, at today's rate until typed.
  Widget _homeTile() {
    final value = _homeValue;
    final rate = _ledger.rates[_currency];
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Tile(
        icon: Glyph.coins,
        label: '折合台幣',
        value: value == null ? '請輸入' : groupDigits(value),
        valueColor: value == null ? Hue.faint : Hue.ink,
        size: 15,
        sub: _home != null || rate == null ? null : '臺銀即期買入 $rate',
        onTap: () async {
          final typed = await _ask('折合台幣', value ?? 0);
          if (typed != null) setState(() => _home = typed);
        },
      ),
    );
  }

  Widget _dateTile() {
    final day = '${_date.month}/${_date.day}';
    return Tile(
      icon: Glyph.calendar,
      label: '日期',
      value: _date == _ledger.today
          ? '今天 $day'
          : '$day 週${weekdayNames[_date.weekday - 1]}',
      size: 15,
      onTap: _pickDate,
    );
  }

  Widget _noteField() {
    if (_viewing && _note.text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: TextField(
        controller: _note,
        minLines: 1,
        maxLines: 3,
        decoration: InputDecoration(
          hintText: '備註（選填）',
          prefixIcon: const Padding(
            padding: EdgeInsets.all(12),
            child: GlyphIcon(Glyph.note, size: 18, color: Hue.accent),
          ),
          filled: true,
          fillColor: Hue.tile,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  List<Widget> _fields() {
    if (_refunded != null) {
      return [
        TileRow([_accountTile('退回到'), _dateTile()]),
        _noteField(),
      ];
    }
    switch (_mode) {
      case ComposeMode.expense || ComposeMode.income:
        final expense = _mode == ComposeMode.expense;
        return [
          if (expense)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Tile(
                icon: Glyph.store,
                label: '商家',
                value: _merchant.isEmpty ? '未填' : _merchant,
                valueColor: _merchant.isEmpty ? Hue.faint : Hue.ink,
                size: 15,
                onTap: _pickMerchant,
              ),
            ),
          _categories(expense),
          TileRow([_accountTile(expense ? '付款帳戶' : '收款帳戶'), _dateTile()]),
          if (_foreign) _homeTile(),
          if (_onCard)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Tile(
                icon: Glyph.card,
                label: '分期付款',
                value: _installments < 2
                    ? '不分期'
                    : '$_installments 期 · 每期 '
                          '${groupDigits(_amount ~/ _installments)}',
                size: 15,
                onTap: _pickInstallments,
              ),
            ),
          _tagBlock(),
          _noteField(),
        ];
      case ComposeMode.transfer:
        final from = _ledger.account(_account);
        final to = _ledger.account(_to);
        return [
          _Block(
            child: Row(
              children: [
                Expanded(
                  child: _AccountEnd(
                    label: '從',
                    account: from,
                    balance: _ledger.balance(from.id),
                    onTap: () async {
                      final picked = await _pickAccount('轉出帳戶', _account);
                      if (picked == null) return;
                      setState(() {
                        _account = picked;
                        _received = null;
                      });
                    },
                  ),
                ),
                const GlyphIcon(Glyph.arrow, size: 22, color: Hue.accent),
                Expanded(
                  child: _AccountEnd(
                    label: '到',
                    account: to,
                    balance: _ledger.balance(to.id),
                    end: true,
                    onTap: () async {
                      final picked = await _pickAccount('轉入帳戶', _to);
                      if (picked == null) return;
                      setState(() {
                        _to = picked;
                        _received = null;
                      });
                    },
                  ),
                ),
              ],
            ),
          ),
          if (_crossing) _receivedTile(),
          TileRow([
            if (_currency == 'TWD')
              Tile(
                icon: Glyph.coins,
                label: '手續費',
                value: groupDigits(_fee),
                valueColor: _fee > 0 ? Hue.negative : Hue.ink,
                size: 15,
                onTap: () async {
                  final value = await _ask('手續費', _fee);
                  if (value != null) setState(() => _fee = value);
                },
              ),
            _dateTile(),
          ]),
          _noteField(),
        ];
      case ComposeMode.investment:
        return _investmentFields();
    }
  }

  /// What a transfer between currencies delivers, at today's rates until
  /// typed.
  Widget _receivedTile() {
    final value = _receivedValue;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Tile(
        icon: Glyph.coins,
        label: '轉入金額',
        value: value == null ? '請輸入' : amountIn(value, _toCurrency),
        valueColor: value == null ? Hue.faint : Hue.ink,
        size: 15,
        sub: _received == null && value != null ? '依臺銀即期匯率換算' : null,
        onTap: () async {
          final typed = await _ask('轉入金額', value ?? 0, unit: _toCurrency);
          if (typed != null) setState(() => _received = typed);
        },
      ),
    );
  }

  /// The categories as a grid of marks, or the parts of a split.
  Widget _categories(bool expense) {
    final parts = _parts;
    final used = parts == null ? 0 : parts.fold(0, (sum, p) => sum + p.$2);
    final left = _amount - used;
    final choices = _categoryChoices();
    final shown = choices.take(6).toList();
    if (shown.isNotEmpty &&
        !shown.contains(_category) &&
        _category.isNotEmpty) {
      shown[shown.length - 1] = _category;
    }
    return _Block(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const IconChip(Glyph.categories),
              const SizedBox(width: 8),
              Text(
                parts == null ? '分類' : '分類 · 拆成 ${parts.length} 筆',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: Hue.accent,
                ),
              ),
              const Spacer(),
              if (parts != null && !_viewing) ...[
                _Chip('均分', _evenly),
                const SizedBox(width: 6),
              ],
              if (expense && !_viewing && !_foreign)
                _Chip(parts == null ? '拆分' : '不拆分', _split),
            ],
          ),
          const SizedBox(height: 8),
          if (parts == null)
            Wrap(
              runSpacing: 8,
              children: [
                for (final name in shown)
                  _CategoryChoice(
                    category: _ledger.category(name),
                    picked: name == _category,
                    onTap: () => setState(() => _category = name),
                  ),
                if (choices.length > shown.length)
                  _CategoryChoice(
                    category: const Category('更多', 'other', Hue.muted),
                    picked: false,
                    onTap: () async {
                      final picked = await _pickCategory(_category);
                      if (picked != null) setState(() => _category = picked);
                    },
                  ),
                if (!_viewing)
                  _CategoryChoice(
                    category: const Category('新增', 'add', Hue.accent),
                    picked: false,
                    onTap: _newCategory,
                  ),
              ],
            )
          else ...[
            for (final (i, (name, value)) in parts.indexed)
              _PartRow(
                category: _ledger.category(name),
                amount: value,
                share: _amount == 0 ? 0 : value / _amount,
                onTap: () => _editPart(i),
              ),
            if (!_viewing)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    _Link('＋ 再拆一個分類', _addPart),
                    const Spacer(),
                    Text(
                      '剩餘 ${groupDigits(left)}',
                      style: const TextStyle(fontSize: 12, color: Hue.muted),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _tagBlock() {
    if (_viewing && _tags.isEmpty) return const SizedBox.shrink();
    return _Block(
      child: Row(
        children: [
          const IconChip(Glyph.ticket),
          const SizedBox(width: 8),
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final tag in _tags) _TagChip('#$tag', solid: true),
                if (!_viewing)
                  GestureDetector(
                    onTap: _pickTags,
                    child: const _TagChip('＋ 標籤', solid: false),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _investmentFields() {
    final code = _holding;
    final held = code == null ? null : _ledger.holding(code);
    final (fee, tax) = _charges;
    final sell = _trade == EntryType.sell;
    final cost = sell && code != null && held != null && _shares <= held.shares
        ? _ledger.saleCost(code, _shares, average: _average)
        : null;
    final settled = settlementDay(_date);
    return [
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Tile(
          icon: Glyph.investment,
          label: '標的',
          value: code == null ? '選擇標的' : '$code ${held?.name ?? ''}',
          size: 15,
          sub: held == null ? null : '持有 ${groupDigits(held.shares)} 股',
          trailing: _viewing
              ? null
              : GestureDetector(
                  onTap: _newHolding,
                  child: const GlyphIcon(Glyph.add, size: 18),
                ),
          onTap: _pickHolding,
        ),
      ),
      if (_trading)
        TileRow([
          Tile(
            icon: Glyph.briefcase,
            label: '股數',
            value: groupDigits(_shares),
            onTap: () async {
              final value = await _ask('股數', _shares, unit: '股');
              if (value == null) return;
              setState(() {
                _shares = value;
                _amount = (_shares * _price).round();
              });
            },
          ),
          Tile(
            icon: Glyph.coins,
            label: '成交價',
            value: _price == _price.roundToDouble()
                ? '${_price.round()}'
                : _price.toStringAsFixed(2),
            onTap: () async {
              final value = await showPriceCalculator(
                context,
                title: '成交價',
                initial: _price,
                color: _color,
              );
              if (value == null) return;
              setState(() {
                _price = value;
                _amount = (_shares * _price).round();
              });
            },
          ),
        ]),
      if (_trade == EntryType.dividend) ...[
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Tile(
            icon: Glyph.briefcase,
            label: _splitShares ? '分割增加股數' : '配股股數',
            value: groupDigits(_shares),
            size: 15,
            onTap: () async {
              final value = await _ask('增加股數', _shares, unit: '股');
              if (value != null) setState(() => _shares = value);
            },
          ),
        ),
        if (_shares > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Segments(
              labels: const ['配股', '分割'],
              selected: _splitShares ? 1 : 0,
              onChanged: (i) => setState(() => _splitShares = i == 1),
            ),
          ),
      ],
      TileRow([
        _accountTile(_trade == EntryType.buy ? '扣款帳戶' : '入帳帳戶'),
        _dateTile(),
      ]),
      if (_trading && sell && !_viewing)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Segments(
            labels: const ['先進先出', '平均成本'],
            selected: _average ? 1 : 0,
            onChanged: (i) => setState(() => _average = i == 1),
          ),
        ),
      if (_trading && _amount > 0)
        _Block(
          child: Column(
            children: [
              _Line('手續費', groupDigits(fee)),
              if (sell) _Line('證交稅', groupDigits(tax)),
              _Line(
                sell ? '實收' : '應付',
                groupDigits(sell ? _amount - fee - tax : _amount + fee),
                strong: true,
              ),
              if (cost != null)
                _Line(
                  '已實現損益',
                  signed(_amount - fee - tax - cost),
                  color: _amount - fee - tax < cost
                      ? Hue.negative
                      : Hue.positive,
                ),
              _Line('交割日', '${settled.month}/${settled.day}'),
            ],
          ),
        ),
      _noteField(),
    ];
  }
}

/// A tinted block of the composer.
class _Block extends StatelessWidget {
  const _Block({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
      decoration: BoxDecoration(
        color: Hue.tile,
        borderRadius: BorderRadius.circular(20),
      ),
      child: child,
    );
  }
}

/// The spending a refund belongs to, at the top of the refund form.
class _OriginalTile extends StatelessWidget {
  const _OriginalTile({required this.ledger, required this.entry});

  final Ledger ledger;
  final Entry entry;

  @override
  Widget build(BuildContext context) {
    final category = ledger.category(entry.category);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Hue.tile,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          IconBadge(iconFor(category.icon), category.color, size: 36),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '原支出 · ${entry.date.month}/${entry.date.day}',
                  style: const TextStyle(fontSize: 12, color: Hue.accent),
                ),
                Text(
                  entry.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          Text(
            spent(entry.amount),
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: Hue.negative,
            ),
          ),
        ],
      ),
    );
  }
}

class _TradeChips extends StatelessWidget {
  const _TradeChips({
    required this.trade,
    required this.locked,
    required this.onChanged,
  });

  final EntryType trade;
  final bool locked;
  final ValueChanged<EntryType> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final (type, label) in const [
          (EntryType.buy, '買進'),
          (EntryType.sell, '賣出'),
          (EntryType.dividend, '股息'),
        ])
          if (!locked || type == trade)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: GestureDetector(
                onTap: locked ? null : () => onChanged(type),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: type == trade ? Hue.accent : Hue.tile,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: type == trade ? Hue.white : Hue.accent,
                    ),
                  ),
                ),
              ),
            ),
      ],
    );
  }
}

class _CategoryChoice extends StatelessWidget {
  const _CategoryChoice({
    required this.category,
    required this.picked,
    required this.onTap,
  });

  final Category category;
  final bool picked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      widthFactor: 0.25,
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Hue.white,
                shape: BoxShape.circle,
                border: picked
                    ? Border.all(color: Hue.accent, width: 2.5)
                    : null,
              ),
              alignment: Alignment.center,
              child: GlyphIcon(
                iconFor(category.icon),
                size: 24,
                color: category.color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              category.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: picked ? FontWeight.w700 : FontWeight.w400,
                color: picked ? Hue.accent : Hue.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PartRow extends StatelessWidget {
  const _PartRow({
    required this.category,
    required this.amount,
    required this.share,
    required this.onTap,
  });

  final Category category;
  final int amount;
  final double share;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0x263B6C80))),
        ),
        child: Row(
          children: [
            IconBadge(iconFor(category.icon), category.color, size: 28),
            const SizedBox(width: 8),
            SizedBox(
              width: 72,
              child: Text(category.name, style: const TextStyle(fontSize: 14)),
            ),
            Expanded(
              child: LinearProgressIndicator(
                value: share.clamp(0.0, 1.0),
                minHeight: 5,
                borderRadius: BorderRadius.circular(3),
                color: category.color,
                backgroundColor: const Color(0x263B6C80),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              groupDigits(amount),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountEnd extends StatelessWidget {
  const _AccountEnd({
    required this.label,
    required this.account,
    required this.balance,
    required this.onTap,
    this.end = false,
  });

  final String label;
  final Account account;
  final int balance;
  final VoidCallback onTap;
  final bool end;

  @override
  Widget build(BuildContext context) {
    final badge = IconBadge(
      accountIcon(account),
      accountColor(account.kind),
      size: 34,
    );
    final text = Column(
      crossAxisAlignment: end
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Hue.muted)),
        Text(
          account.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        Text(
          '餘額 ${amountIn(balance, account.currency)}',
          style: const TextStyle(fontSize: 11, color: Hue.muted),
        ),
      ],
    );
    return InkWell(
      onTap: onTap,
      child: Row(
        mainAxisAlignment: end
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: end
            ? [Flexible(child: text), const SizedBox(width: 8), badge]
            : [badge, const SizedBox(width: 8), Flexible(child: text)],
      ),
    );
  }
}

/// One line of a trade's sums.
class _Line extends StatelessWidget {
  const _Line(
    this.label,
    this.value, {
    this.strong = false,
    this.color = Hue.ink,
  });

  final String label;
  final String value;
  final bool strong;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Text(label, style: const TextStyle(fontSize: 13.5)),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontSize: strong ? 16 : 14.5,
              fontWeight: strong ? FontWeight.w700 : FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// A small white button in a block's heading, such as 拆分.
class _Chip extends StatelessWidget {
  const _Chip(this.label, this.onTap);

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Hue.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: Hue.accent,
            ),
          ),
        ),
      ),
    );
  }
}

class _Link extends StatelessWidget {
  const _Link(this.label, this.onTap);

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Text(
          label,
          style: const TextStyle(fontSize: 12.5, color: Hue.accent),
        ),
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip(this.label, {required this.solid});

  final String label;
  final bool solid;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: solid ? Hue.accent : Hue.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 12, color: solid ? Hue.white : Hue.accent),
      ),
    );
  }
}

/// A merchant's name, typed or picked from those used before.
class _MerchantPicker extends StatefulWidget {
  const _MerchantPicker({required this.known, required this.initial});

  final List<String> known;
  final String initial;

  @override
  State<_MerchantPicker> createState() => _MerchantPickerState();
}

class _MerchantPickerState extends State<_MerchantPicker> {
  late final _text = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final typed = _text.text.trim();
    final matches = [
      for (final name in widget.known)
        if (typed.isEmpty || name.toLowerCase().contains(typed.toLowerCase()))
          name,
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _text,
          autofocus: true,
          onChanged: (_) => setState(() {}),
          onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
          decoration: InputDecoration(
            hintText: '商家名稱',
            filled: true,
            fillColor: Hue.tile,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            children: [
              if (typed.isNotEmpty && !widget.known.contains(typed))
                ListTile(
                  leading: const GlyphIcon(Glyph.add, color: Hue.accent),
                  title: Text('新增「$typed」'),
                  onTap: () => Navigator.of(context).pop(typed),
                ),
              for (final name in matches.take(12))
                ListTile(
                  leading: const GlyphIcon(Glyph.store, color: Hue.accent),
                  title: Text(name),
                  onTap: () => Navigator.of(context).pop(name),
                ),
              if (widget.initial.isNotEmpty)
                ListTile(
                  leading: const GlyphIcon(Glyph.close, color: Hue.muted),
                  title: const Text('不記商家'),
                  onTap: () => Navigator.of(context).pop(''),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Tags to put on an entry: those in use, and new ones.
class _TagPicker extends StatefulWidget {
  const _TagPicker({required this.known, required this.initial});

  final List<String> known;
  final List<String> initial;

  @override
  State<_TagPicker> createState() => _TagPickerState();
}

class _TagPickerState extends State<_TagPicker> {
  late final _picked = [...widget.initial];
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _add() {
    final tag = _text.text.trim().replaceAll('#', '');
    if (tag.isEmpty) return;
    setState(() {
      if (!_picked.contains(tag) && _picked.length < 16) _picked.add(tag);
      _text.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final all = {...widget.known, ..._picked}.toList();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final tag in all)
              FilterChip(
                label: Text('#$tag'),
                selected: _picked.contains(tag),
                onSelected: (on) => setState(() {
                  if (on) {
                    if (_picked.length < 16) _picked.add(tag);
                  } else {
                    _picked.remove(tag);
                  }
                }),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _text,
                onSubmitted: (_) => _add(),
                decoration: InputDecoration(
                  hintText: '新標籤',
                  filled: true,
                  fillColor: Hue.tile,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: '加入',
              onPressed: _add,
              icon: const GlyphIcon(Glyph.add, color: Hue.accent),
            ),
          ],
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_picked),
          style: FilledButton.styleFrom(
            backgroundColor: Hue.accent,
            minimumSize: const Size.fromHeight(44),
          ),
          child: const Text('完成'),
        ),
      ],
    );
  }
}
