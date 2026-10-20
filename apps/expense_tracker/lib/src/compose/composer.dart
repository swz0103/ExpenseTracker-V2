import 'package:flutter/material.dart';

import '../look/figures.dart';
import '../look/glyphs.dart';
import '../look/icons.dart';
import '../look/theme.dart';
import '../look/widgets.dart';
import '../model/checks.dart';
import '../model/ledger.dart';
import '../model/trading.dart';
import '../pages/account_editor.dart';
import '../pages/categories_page.dart';
import '../pages/dialogs.dart';
import 'calculator.dart';
import 'pickers.dart';

part 'composer_fields.dart';
part 'composer_widgets.dart';

/// The four tabs of the composer.
enum ComposeMode {
  expense('支出', Glyph.bag, Hue.negative, Hue.expenseSoft),
  income('收入', Glyph.income, Hue.positive, Hue.incomeSoft),
  transfer('轉帳', Glyph.transfer, Hue.transfer, Hue.transferSoft),
  lend('代墊', Glyph.heart, Hue.receivable, Hue.investmentSoft),
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
final _drafts = <ComposeMode, Entry>{};

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
}) async {
  if (!await ensureAccount(context, ledger) || !context.mounted) return null;
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

  /// The 二代健保 premium withheld from a cash dividend, as typed; null
  /// works it out from the amount and day.
  int? _premium;
  var _installments = 0;
  var _average = false;
  var _splitShares = false;

  /// A dividend that changes the shares held, opened from its link: most
  /// dividends are cash only.
  var _shareChange = false;

  /// A capital reduction: the shares go down and cash comes back.
  var _reduce = false;

  /// 代墊: money coming back from the person rather than paid for them.
  var _back = false;
  final _note = TextEditingController();
  String? _problem;

  /// Shows the merchant, tags and note: hidden until asked for, or until
  /// an entry that has them is opened, so a quick entry stays short.
  var _more = false;

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
      if (draft != null) _restoreDraft(draft);
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
    _more =
        entry.merchant.isNotEmpty ||
        entry.tags.isNotEmpty ||
        entry.note.isNotEmpty;
    _parts = entry.parts.isEmpty ? null : [...entry.parts];
    _fee = entry.type == EntryType.transfer ? entry.fee : 0;
    _home = entry.home;
    _received = entry.received;
    _premium = entry.type == EntryType.dividend ? entry.tax : null;
    _installments = entry.installments;
    _average = entry.average;
    _splitShares = entry.split;
    _shareChange = entry.type == EntryType.dividend && entry.shares != 0;
    _reduce = entry.isReduction;
    if (_reduce) _shares = -entry.shares;
    if (entry.type == EntryType.buy || entry.type == EntryType.sell) {
      _tradeFee = entry.fee;
      _tradeTax = entry.tax;
    }
  }

  /// A trade's broker fee and tax as typed, or as it was saved; null
  /// takes the suggestion.
  int? _tradeFee;
  int? _tradeTax;

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
    _tradeFee = null;
    _tradeTax = null;
    _home = null;
    _received = null;
    _premium = null;
    _installments = 0;
    _average = false;
    _splitShares = false;
    _shareChange = false;
    _reduce = false;
    _back = false;
    _problem = null;
    if (_mode == ComposeMode.lend) {
      // Paid from the main account, for the first person owing.
      final main = _ledger.mainAccount;
      if (main.isNotEmpty) _account = main;
      _to = _people.isEmpty ? '' : _people.first.id;
    }
  }

  /// The accounts that keep what someone owes, one per person.
  List<Account> get _people => [
    for (final a in _ledger.openAccounts)
      if (a.kind == AccountKind.receivable) a,
  ];

  /// Categories of this tab, the most used lately first.
  List<String> _categoryChoices() =>
      _ledger.categoriesByUse(income: _mode == ComposeMode.income);

  /// Brings back a draft put aside, on accounts still open.
  void _restoreDraft(Entry draft) {
    _load(draft);
    if (draft.isInvestment) _trade = draft.type;
    final open = {for (final a in _ledger.openAccounts) a.id};
    if (!open.contains(_account)) _account = _ledger.openAccounts.first.id;
    if (!open.contains(_to)) _to = _account;
  }

  void _switch(ComposeMode mode) {
    if (mode == _mode) return;
    setState(() {
      _mode = mode;
      _fresh();
      final draft = _drafts[mode];
      if (draft != null && widget.entry == null) _restoreDraft(draft);
    });
  }

  EntryType get _type => switch (_mode) {
    ComposeMode.expense => EntryType.expense,
    ComposeMode.income => EntryType.income,
    ComposeMode.transfer || ComposeMode.lend => EntryType.transfer,
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
      EntryType.transfer when _mode == ComposeMode.lend => '代墊與還款',
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
      EntryType.transfer when _mode == ComposeMode.lend =>
        _back ? '記下還款' : '記下代墊',
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

  /// A transfer with a fee field: from an NT$ account, whose fee counts
  /// as NT$ spending, and not to a card, whose payment carries none.
  bool get _takesFee =>
      _currency == 'TWD' && _ledger.account(_to).kind != AccountKind.card;

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

  /// The premium withheld from the cash dividend being written.
  int get _withheld => _premium ?? dividendPremium(_amount, _date);

  /// The broker's fee and tax the ledger's Taiwan rules suggest for the
  /// trade being written.
  (int, int) get _suggested {
    final tax = _type == EntryType.sell
        ? saleTax(_holding ?? '', _amount, _shares, _date)
        : 0;
    return (brokerFee(_amount, _shares), tax);
  }

  /// The trade's fee and tax: as typed, else as suggested.
  (int, int) get _charges {
    if (_type != EntryType.buy && _type != EntryType.sell) return (0, 0);
    final (fee, tax) = _suggested;
    return (_tradeFee ?? fee, _tradeTax ?? tax);
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
      _premium = null;
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

  /// An open account; for a refund, one in the purchase's currency.
  Future<String?> _pickAccount(String title, String selected) {
    final refunded = _refunded;
    final currency = refunded == null
        ? null
        : _ledger.account(refunded.account).currency;
    return pickOption<String>(
      context,
      title: title,
      selected: selected,
      columns: 3,
      options: [
        for (final a in _ledger.openAccounts)
          if (currency == null || a.currency == currency)
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
      ledger: _ledger,
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
        _shareChange = false;
        _reduce = false;
      }
      _tradeFee = null;
      _tradeTax = null;
      _trade = trade;
    });
  }

  /// The parts of a split being written; none for a foreign amount.
  List<(String, int)>? get _splitParts =>
      _type == EntryType.expense && !_foreign ? _parts : null;

  /// A dividend that changes the shares held: a stock dividend, a split
  /// or, with [_reduce], a capital reduction.
  bool get _stock => _type == EntryType.dividend && _shares > 0;
  bool get _reducing => _stock && _reduce;

  /// Why the entry cannot be kept yet; null when it can. The ledger's
  /// own checks, and a split that must add up to the amount.
  String? get _check {
    if (_mode == ComposeMode.lend && _to.isEmpty) return '請選擇代墊對象';
    final problem = _ledger.problemWith(_build(), replacing: widget.entry);
    if (problem != null) return problem;
    final splitTotal = _splitParts?.fold(0, (sum, p) => sum + p.$2);
    if (splitTotal != null && splitTotal != _amount) {
      return '拆分的金額要等於總額（差 ${groupDigits(_amount - splitTotal)}）';
    }
    return null;
  }

  bool get _lendingBack => _mode == ComposeMode.lend && _back;

  /// The entry as the form now stands.
  Entry _build() {
    final type = _type;
    final parts = _splitParts;
    final (fee, tax) = _charges;
    return Entry(
      id: widget.entry?.id ?? _ledger.newId(),
      date: _date,
      type: type,
      amount: _amount,
      // Paid back: from the person's account into the chosen one.
      account: _lendingBack ? _to : _account,
      category: switch (type) {
        EntryType.transfer => '轉帳',
        EntryType.dividend => '股息收入',
        EntryType.buy || EntryType.sell => '投資',
        _ => parts == null || parts.isEmpty ? _category : parts.first.$1,
      },
      note: _note.text.trim(),
      to: _lendingBack
          ? _account
          : type == EntryType.transfer
          ? _to
          : null,
      holding: _mode == ComposeMode.investment ? _holding : null,
      shares: _mode != ComposeMode.investment
          ? 0
          : _reducing
          ? -_shares
          : _shares,
      recurring: widget.entry?.recurring ?? widget.draft?.recurring,
      merchant: type == EntryType.expense ? _merchant : '',
      tags: type == EntryType.expense || type == EntryType.income ? _tags : [],
      parts: parts != null && parts.length > 1 ? parts : const [],
      fee: type == EntryType.transfer ? (_takesFee ? _fee : 0) : fee,
      tax: type == EntryType.dividend ? (_reducing ? 0 : _withheld) : tax,
      refundOf: _refunded?.id ?? widget.entry?.refundOf,
      installments: _onCard ? _installments : 0,
      average: type == EntryType.sell && _average,
      split: _stock && _splitShares && !_reducing,
      home: _foreign ? _homeValue : null,
      received: _crossing ? _receivedValue : null,
    );
  }

  void _submit() {
    final problem = _check;
    if (problem != null) {
      setState(() => _problem = problem);
      return;
    }
    final entry = _build();
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
    _drafts[_mode] = _build();
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
                    _ when _mode == ComposeMode.lend => _back ? '還款金額' : '代墊金額',
                    EntryType.transfer => '轉出金額',
                    EntryType.buy || EntryType.sell => '成交金額',
                    EntryType.dividend when _reducing => '退還股款',
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

  /// Applies [change] while the form is still on screen: the field
  /// builders in composer_fields.dart run it after a dialog closes.
  void _set(VoidCallback change) {
    if (mounted) setState(change);
  }
}
