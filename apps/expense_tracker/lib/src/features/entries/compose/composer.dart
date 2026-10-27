import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../core/look/dialogs.dart';
import '../../../core/look/figures.dart';
import '../../../core/look/glyphs.dart';
import '../../../core/look/icons.dart';
import '../../../core/look/theme.dart';
import '../../../core/look/widgets.dart';
import '../../../core/ledger/checks.dart';
import '../../../core/ledger/ledger.dart';
import '../../../core/ledger/record_json.dart';
import '../../../core/ledger/trading.dart';
import '../../accounts/compose/account_editor.dart';
import '../../../core/ui/amount_pad.dart';
import '../../../core/ui/calculator.dart';
import '../../../core/ui/entry_tile.dart' show holdingLabel;
import '../../categories/compose/category_editor.dart';
import '../../../core/ui/pickers.dart';
import '../model/compose_form.dart';
import '../model/receipt_photos.dart';

export '../model/compose_form.dart' show ComposeMode;

part 'composer_fields.dart';
part 'composer_investment.dart';
part 'composer_lend.dart';
part 'composer_widgets.dart';

/// How each kind of record looks on its tab.
extension ComposeModeLook on ComposeMode {
  Glyph get icon => switch (this) {
    ComposeMode.expense => Glyph.bag,
    ComposeMode.income => Glyph.income,
    ComposeMode.transfer => Glyph.transfer,
    ComposeMode.lend => Glyph.heart,
    ComposeMode.investment => Glyph.investment,
  };

  Color get color => switch (this) {
    ComposeMode.expense => Hue.negative,
    ComposeMode.income => Hue.positive,
    ComposeMode.transfer => Hue.transfer,
    ComposeMode.lend => Hue.receivable,
    ComposeMode.investment => Hue.investment,
  };
}

/// A form put aside with 暫存: the entry as it stood and the receipt
/// photo chosen for it, which is not part of the entry until it is saved.
final class _Draft {
  const _Draft(this.entry, this.receipt);

  final Entry entry;
  final String? receipt;

  String toJson() =>
      jsonEncode({'entry': entryToJson(entry), 'receipt': ?receipt});

  static _Draft? read(String? json) {
    if (json == null) return null;
    try {
      final map = jsonDecode(json) as Map<String, Object?>;
      return _Draft(
        entryFromJson(map['entry']! as Map<String, Object?>),
        map['receipt'] as String?,
      );
    } on Object {
      return null;
    }
  }
}

/// Forms put aside with 暫存, by tab, kept in the ledger they were
/// written for, so they outlast the app being closed by the phone.
extension type const _Drafts(Ledger ledger) {
  _Draft? operator [](ComposeMode tab) => _Draft.read(ledger.draft(tab.name));

  void operator []=(ComposeMode tab, _Draft draft) =>
      ledger.setDraft(tab.name, draft.toJson());

  void remove(ComposeMode tab) => ledger.setDraft(tab.name, null);
}

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
  ReceiptPhotos? photos,
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
      photos: photos,
    ),
    // The composer draws its own, between 重填 and 關閉.
    handle: false,
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
    this.photos,
  });

  final Ledger ledger;
  final EntryType type;

  /// The entry being changed, if any.
  final Entry? entry;

  /// A new entry's starting values, such as a card payment.
  final Entry? draft;

  /// The spending being refunded, for a refund.
  final Entry? refundOf;

  /// The phone's receipt photos; none in the preview, which hides them.
  final ReceiptPhotos? photos;

  @override
  State<Composer> createState() => _ComposerState();
}

class _ComposerState extends State<Composer> with WidgetsBindingObserver {
  /// The fields and their rules.
  late final ComposeForm _f = ComposeForm(
    widget.ledger,
    type: widget.type,
    editing: widget.entry,
    draft: widget.draft,
    refunded: widget.refundOf,
  );

  final _note = TextEditingController();
  String? _problem;

  /// An entry opened from a list is shown first; 編輯 unlocks it.
  late var _viewing = widget.entry != null;

  Ledger get _ledger => widget.ledger;

  /// This ledger's forms put aside, by tab.
  _Drafts get _drafts => _Drafts(_ledger);

  /// The form was put aside as the app went to the background, in case
  /// the phone closes it there; taken back when the app returns.
  var _keptAway = false;

  /// The draft that tab had before, put back when the app returns.
  String? _before;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_takeLeftover());
    if (widget.entry == null && widget.draft == null && _f.refunded == null) {
      final draft = _drafts[_f.mode];
      if (draft != null) _f.restore(draft.entry, draft.receipt);
    }
    _note
      ..text = _f.note
      ..addListener(() => _f.note = _note.text);
    _syncKeys();
  }

  /// Whether the amount is typed on keys laid in the form, so a quick
  /// entry needs no calculator: a new entry other than a trade.
  bool get _inline =>
      !_viewing &&
      widget.entry == null &&
      _f.refunded == null &&
      _f.mode != ComposeMode.investment;

  /// What the keys in the form have typed.
  var _keys = AmountKeys('');

  bool get _cents => takesCents(_f.currency);

  /// A key of the form's keys: the amount follows what they come to.
  void _padKey(String key) => setState(() {
    if (_keys.decimal != _cents) {
      _keys = AmountKeys(_keys.expression, decimal: _cents);
    }
    _keys.press(key);
    final typed = _keys.result;
    _f.setAmount(_cents ? (typed * 100).round() : typed.round());
  });

  /// Starts the keys from the amount, after it was set some other way.
  void _syncKeys() {
    _keys = AmountKeys(
      _f.amount == 0 ? '' : plainAmount(_f.amount, _f.currency),
      decimal: _cents,
    );
  }

  /// Shows the form's note again after the form filled it afresh.
  void _showNote() {
    if (_note.text != _f.note) _note.text = _f.note;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _note.dispose();
    super.dispose();
  }

  /// Starts the current tab afresh.
  void _fresh() {
    _f.fresh();
    _problem = null;
    _showNote();
    _syncKeys();
  }

  /// 代墊 from the expense tab, 對方還錢 from the income tab.
  void _lend({required bool back}) {
    _set(() => _f.lend(back: back));
    if (_f.people.isEmpty) unawaited(_pickPerson());
  }

  /// A category picked: back to a plain expense or income from 代墊.
  void _pickCategoryName(String name) => _set(() => _f.pickCategory(name));

  /// Moves to another tab: the fields start afresh, or as that tab's
  /// draft left them. A receipt photo already chosen stays, unless the
  /// draft brings its own: the photo is of what was bought or paid,
  /// whichever kind of entry it turns out to be.
  void _switch(ComposeMode mode) {
    if (mode == _f.mode) return;
    setState(() {
      _f.switchTo(mode);
      final draft = _drafts[mode];
      if (draft != null && widget.entry == null) {
        final photo = _f.receipt;
        _f.restore(draft.entry, draft.receipt);
        _f.receipt ??= photo;
      }
      _problem = null;
      _showNote();
      _syncKeys();
    });
  }

  Color get _color {
    if (_f.refunded != null) return Hue.positive;
    if (_f.mode != ComposeMode.investment) return _f.tab.color;
    return _f.trade == EntryType.sell ? Hue.positive : Hue.investment;
  }

  /// What the tabs do not say: an entry being changed, money paid for
  /// someone or paid back, a refund. Shown as small tags under the top
  /// row; a new plain entry needs none.
  List<(String, Color)> get _marks => [
    if (_f.refunded != null) ('退款', Hue.positive),
    if (widget.entry != null && !_viewing) ('編輯中', Hue.accent),
    if (_f.mode == ComposeMode.lend)
      (_f.back ? '還款' : '代墊', Hue.receivable),
  ];

  String get _action {
    if (widget.entry != null) return '儲存修改';
    if (_f.refunded != null) return '記下退款';
    return switch (_f.type) {
      EntryType.expense => '記下支出',
      EntryType.income => '記下收入',
      EntryType.transfer when _f.mode == ComposeMode.lend =>
        _f.back ? '記下還款' : '記下代墊',
      EntryType.transfer => '確認轉帳',
      EntryType.buy => '記下買進',
      EntryType.sell => '記下賣出',
      EntryType.dividend => '記下股息',
    };
  }

  Future<int?> _ask(String title, int initial, {String unit = homeCode}) {
    return showCalculator(
      context,
      title: title,
      initial: initial,
      color: _color,
      unit: unit,
    );
  }

  Future<void> _calculate() async {
    final value = await _ask('輸入金額', _f.amount, unit: _f.currency);
    if (value == null) return;
    setState(() {
      _f.setAmount(value);
      _syncKeys();
    });
  }

  Future<void> _pickDate() async {
    final marked = {
      for (final e in _ledger.entriesIn(_f.date.year, _f.date.month)) e.date,
    };
    final day = await pickDate(
      context,
      title: '入帳日期',
      selected: _f.date,
      latest: _ledger.today,
      marked: marked,
    );
    if (day != null) setState(() => _f.date = day);
  }

  /// An open account; for a refund, one in the purchase's currency.
  Future<String?> _pickAccount(String title, String selected) {
    final refunded = _f.refunded;
    final currency = refunded == null
        ? null
        : _ledger.account(refunded.account).currency;
    return pickOption<String>(
      context,
      title: title,
      selected: selected,
      columns: 3,
      options: accountOptions(_ledger, currency: currency),
    );
  }

  Future<String?> _pickCategory(String? selected) {
    final income = _f.mode == ComposeMode.income;
    return pickOption<String>(
      context,
      title: income ? '收入分類' : '支出分類',
      selected: selected,
      options: categoryOptions(_ledger, income: income),
    );
  }

  Future<void> _pickHolding() async {
    final picked = await pickOption<String>(
      context,
      title: '投資標的',
      selected: _f.holding,
      columns: 3,
      options: [
        for (final h in _ledger.holdings)
          Option(h.code, holdingLabel(h), Glyph.investment, Hue.investment),
      ],
    );
    if (picked != null) setState(() => _f.holding = picked);
  }

  Future<void> _newHolding() async {
    final typed = await askText(context, '新增標的代號');
    if (typed == null) return;
    final code = tidyCode(typed);
    if (code.isEmpty) return;
    setState(() => _f.holding = code);
    if (!quotable(code) && mounted) {
      showNote(context, '證交所與櫃買中心沒有「$code」這個代號，市值會以成本估算');
    }
  }

  Future<void> _pickMerchant() async {
    final picked = await showChildPage<String>(
      context,
      title: '商家',
      builder: (_) =>
          _MerchantPicker(known: _ledger.merchants, initial: _f.merchant),
    );
    if (picked == null) return;
    setState(() => _f.pickMerchant(picked));
  }

  Future<void> _pickTags() async {
    final picked = await showChildPage<List<String>>(
      context,
      title: '標籤',
      builder: (_) => _TagPicker(known: _ledger.tags, initial: _f.tags),
    );
    if (picked != null) setState(() => _f.tags = picked);
  }

  Future<void> _pickInstallments() async {
    final picked = await pickOption<int>(
      context,
      title: '分期付款',
      selected: _f.installments,
      columns: 3,
      options: [
        for (final n in const [0, 3, 6, 12, 24, 30])
          Option(n, n == 0 ? '不分期' : '$n 期', Glyph.card, Hue.card),
      ],
    );
    if (picked != null) setState(() => _f.installments = picked);
  }

  Future<void> _newCategory() async {
    final income = _f.mode == ComposeMode.income;
    final count = _ledger.categories.length;
    final made = await showCategoryEditor(
      context,
      title: income ? '新增收入分類' : '新增支出分類',
      initial: Category(
        '',
        income ? 'income' : 'other',
        Hue.categoryColors[count % Hue.categoryColors.length],
        income: income,
      ),
      colors: Hue.categoryColors,
      ledger: _ledger,
    );
    if (made == null) return;
    _ledger.addCategory(made);
    setState(() => _f.category = made.name);
  }

  void _split() => setState(_f.toggleSplit);

  void _evenly() => setState(_f.evenly);

  Future<void> _addPart() async {
    final name = await _pickCategory(null);
    if (name == null) return;
    setState(() => _f.addPart(name));
  }

  Future<void> _editPart(int index) async {
    final parts = _f.parts;
    if (parts == null) return;
    final (name, value) = parts[index];
    final amount = await _ask(name, value);
    if (amount == null) return;
    setState(() => _f.setPart(index, amount));
  }

  void _changeTrade(EntryType trade) => setState(() => _f.changeTrade(trade));

  /// A receipt photo the camera took while the phone closed the app goes
  /// with the next new entry.
  Future<void> _takeLeftover() async {
    final photos = widget.photos;
    if (photos == null || widget.entry != null || _f.refunded != null) return;
    final String? name;
    try {
      name = await photos.takeLeftover();
    } on Object {
      return;
    }
    if (name == null || !mounted) return;
    setState(() => _f.receipt = name);
  }

  /// A new entry written part way is kept as the app leaves, so a phone
  /// short of memory closing the app loses nothing: it is there, with
  /// its photo, the next time 記一筆 opens. Back in time, it is taken
  /// away again, unless it was put aside with 暫存 before.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (widget.entry != null || _viewing || _f.refunded != null) return;
    switch (state) {
      case AppLifecycleState.paused || AppLifecycleState.hidden:
        if (_keptAway || (_f.amount == 0 && _f.receipt == null)) return;
        try {
          final draft = _Draft(_f.build(), _f.receipt);
          _before = _ledger.draft(_f.tab.name);
          _drafts[_f.tab] = draft;
          _keptAway = true;
        } on Object {
          // A form that cannot be built yet is not worth keeping.
        }
      case AppLifecycleState.resumed:
        if (!_keptAway) return;
        _keptAway = false;
        _ledger.setDraft(_f.tab.name, _before);
      default:
        break;
    }
  }

  void _submit() {
    final problem = _f.problem;
    if (problem != null) {
      setState(() => _problem = problem);
      return;
    }
    final entry = _f.build();
    try {
      if (widget.entry == null) {
        _ledger.add(entry, receipt: _f.receipt);
      } else {
        _ledger.replace(entry, receipt: _f.receipt);
      }
    } on StateError catch (error) {
      setState(() => _problem = error.message);
      return;
    }
    _drafts.remove(_f.tab);
    Navigator.of(context).pop((ComposeOutcome.saved, entry));
  }

  void _putAside() {
    _keptAway = false;
    _drafts[_f.tab] = _Draft(_f.build(), _f.receipt);
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
    final refunded = _f.refunded;
    final most = refunded == null
        ? 0
        : _ledger.refundable(refunded) + (entry?.amount ?? 0);
    final canRefund =
        _viewing &&
        entry != null &&
        entry.type == EntryType.expense &&
        _ledger.refundable(entry) > 0;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 重填, the handle to drag the sheet by, and 關閉 on one row:
          // the tabs below already say what is being written.
          Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Visibility.maintain(
                    visible: !_viewing && entry == null,
                    child: TextButton(
                      onPressed: () => setState(() {
                        _drafts.remove(_f.tab);
                        _f.mode = _f.tab;
                        _fresh();
                      }),
                      style: TextButton.styleFrom(foregroundColor: Hue.ink),
                      child: const Text('重填', style: TextStyle(fontSize: 13)),
                    ),
                  ),
                ),
              ),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Hue.faint,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    tooltip: '關閉',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const GlyphIcon(
                      Glyph.close,
                      size: 20,
                      color: Hue.muted,
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_marks.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 6,
                children: [
                  for (final (label, color) in _marks) Pill(label, color: color),
                ],
              ),
            ),
          if (refunded != null)
            _OriginalTile(ledger: _ledger, entry: refunded)
          else if (_viewing)
            Center(child: Pill(_f.mode.label, color: _f.mode.color))
          else if (entry == null)
            Segments(
              labels: [for (final m in ComposeForm.tabs) m.label],
              selected: ComposeForm.tabs.indexOf(_f.tab),
              selectedColor: _f.tab.color,
              onChanged: (i) => _switch(ComposeForm.tabs[i]),
            ),
          if (_f.mode == ComposeMode.investment && refunded == null) ...[
            const SizedBox(height: 8),
            _TradeChips(
              trade: _f.trade,
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
                // A trade's amount is in its settlement, under shares and
                // price.
                if (!_f.trading)
                  Tile(
                  hero: true,
                  icon: Glyph.calculator,
                  label: switch (_f.type) {
                    _ when refunded != null => '退款金額',
                    _ when _f.mode == ComposeMode.lend => _f.back ? '還款金額' : '代墊金額',
                    EntryType.transfer => '轉出金額',
                    EntryType.buy || EntryType.sell => '成交金額',
                    EntryType.dividend when _f.reducing => '退還股款',
                    _ => '金額',
                  },
                  value: '${_f.sign}${amountIn(_f.amount, _f.currency)}',
                  valueColor: _color,
                  size: 34,
                  sub: refunded == null
                      ? null
                      : '最多可退 ${_ledger.moneyIn(most, _f.currency)}',
                  onTap: _f.trading ? null : _calculate,
                ),
                ..._fields(),
              ],
            ),
          ),
          // The categories over the keys: pick one, type the amount, save.
          if (_inline) ...[
            if (_f.mode != ComposeMode.transfer)
              _categories(_f.tab == ComposeMode.expense),
            const SizedBox(height: 10),
            AmountPad(onKey: _padKey, decimal: _cents),
          ],
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
