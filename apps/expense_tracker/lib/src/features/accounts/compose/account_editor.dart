import 'package:core/foundation_values.dart' show Currency;
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
import '../../debts/model/loan_plan.dart';
import '../model/account_form.dart';
import '../ui/account_card.dart' show cardKindLabel;
import '../ui/accounts.dart' show walletKinds;

part 'loan_fields.dart';

/// True when [ledger] has an open account, after offering to add one if
/// it has none: entries, imports and recurring items all need one.
Future<bool> ensureAccount(BuildContext context, Ledger ledger) async {
  if (ledger.openAccounts.isNotEmpty) return true;
  final add = await confirm(context, '先新增一個帳戶，才能記帳', '新增帳戶');
  if (add && context.mounted) await editAccount(context, ledger);
  return ledger.openAccounts.isNotEmpty && context.mounted;
}

/// Opens the account form: a new account, or [account] to change. Saving
/// writes to [ledger] directly. True when the account was deleted or
/// archived, so the page showing it should go back.
Future<bool> editAccount(
  BuildContext context,
  Ledger ledger, {
  Account? account,
}) async {
  final gone = await showSheet<bool>(
    context,
    (_) => _AccountEditor(ledger: ledger, account: account),
  );
  return gone ?? false;
}

/// Opens the form of a loan: a new one, from 代墊與借貸, or [loan] to
/// change. True when it was deleted or archived.
Future<bool> editLoan(
  BuildContext context,
  Ledger ledger, {
  Account? loan,
}) async {
  final gone = await showSheet<bool>(
    context,
    (_) =>
        _AccountEditor(ledger: ledger, account: loan, kind: AccountKind.loan),
  );
  return gone ?? false;
}

class _AccountEditor extends StatefulWidget {
  const _AccountEditor({required this.ledger, this.account, this.kind});

  final Ledger ledger;
  final Account? account;

  /// The kind a new account opens as.
  final AccountKind? kind;

  @override
  State<_AccountEditor> createState() => _AccountEditorState();
}

class _AccountEditorState extends State<_AccountEditor> {
  late final _old = widget.account;

  /// The fields and what saving does.
  late final _f = AccountForm(widget.ledger, old: _old)
    ..kind = _old?.kind ?? widget.kind ?? AccountKind.bank;
  late final TextEditingController _principal = TextEditingController(
    text: _f.principal,
  )..addListener(() => setState(() => _f.principal = _principal.text));

  /// A loan's form: no kinds, marks or currencies, but what was borrowed
  /// and, for a new one, where the money went.
  bool get _loanForm => _f.kind == AccountKind.loan;
  // The card on top shows what is typed as it is typed.
  late final TextEditingController _name = TextEditingController(text: _f.name)
    ..addListener(() => setState(() => _f.name = _name.text));
  late final TextEditingController _balance = TextEditingController(
    text: _f.balance,
  )..addListener(() => setState(() => _f.balance = _balance.text));
  late final TextEditingController _limit = TextEditingController(
    text: _f.limit,
  )..addListener(() => _f.limit = _limit.text);

  late final TextEditingController _rate = TextEditingController(text: _f.rate)
    ..addListener(() => setState(() => _f.rate = _rate.text));
  late final TextEditingController _months = TextEditingController(
    text: _f.months,
  )..addListener(() => setState(() => _f.months = _months.text));

  /// The currencies offered in the row; the rest open from 更多.
  static const _common = [homeCode, 'USD', 'JPY', 'EUR', 'CNY'];

  /// Lets the loan's fields in the part file set state.
  void _set(VoidCallback change) => setState(change);

  @override
  void dispose() {
    _name.dispose();
    _balance.dispose();
    _principal.dispose();
    _limit.dispose();
    _rate.dispose();
    _months.dispose();
    super.dispose();
  }

  void _save() {
    if (_f.save()) Navigator.of(context).pop();
  }

  /// Archives the account, or brings it back. One with money left is
  /// settled first: its balance moves to the account picked.
  Future<void> _archive() async {
    final old = _old;
    if (old == null) return;
    final ledger = widget.ledger;
    final left = ledger.balance(old.id);
    if (!old.archived && left != 0) {
      final into = await pickOption<String>(
        context,
        title: left > 0 ? '餘額轉到哪個帳戶' : '由哪個帳戶結清欠款',
        selected: null,
        columns: 3,
        options: accountOptions(
          ledger,
          currency: old.currency,
          where: (a) => a.id != old.id && !a.kind.isDebt,
        ),
      );
      if (into == null) return;
      ledger.add(AccountForm.settlement(ledger, old, into));
    }
    ledger.updateAccount(old.copyWith(archived: !old.archived));
    if (mounted) Navigator.of(context).pop(!old.archived);
  }

  Future<void> _remove() async {
    final old = _old;
    if (old == null) return;
    final ok = await confirm(context, '刪除「${old.name}」？', '刪除', danger: true);
    if (!ok || !mounted) return;
    widget.ledger.removeAccount(old.id);
    Navigator.of(context).pop(true);
  }

  Future<void> _pickDay(bool closing) async {
    final picked = await showSheet<int>(
      context,
      (context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              closing ? '結帳日' : '繳款日',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 7,
              shrinkWrap: true,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              children: [
                for (var day = 1; day <= 28; day++)
                  _DayKey(
                    day: day,
                    picked: day == (closing ? _f.closing : _f.due),
                    onTap: () => Navigator.of(context).pop(day),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    setState(() {
      if (closing) {
        _f.closing = picked;
      } else {
        _f.due = picked;
      }
    });
  }

  /// The kinds the form offers: those of 我的帳戶, and the account's own
  /// when it is of another.
  List<AccountKind> get _kinds {
    final old = _old;
    return [
      ...walletKinds,
      if (old != null && !walletKinds.contains(old.kind)) old.kind,
    ];
  }

  /// The six marks shown for the kind, with the account's own in the
  /// last place when it is not one of them.
  List<String> get _usual {
    final usual = usualAccountIcons(_f.kind);
    final own = _f.icon;
    if (usual.isEmpty) return own == null ? const [] : [own];
    if (own == null || usual.contains(own)) return usual;
    return [...usual.take(usual.length - 1), own];
  }

  /// The account as the form stands, for its colour and label.
  Account get _preview => Account(
    _old?.id ?? '',
    _f.name.trim(),
    _f.kind,
    0,
    icon: _f.icon,
    dueDay: _f.card ? _f.due : null,
    currency: _f.foreignAllowed ? _f.currency : homeCode,
    color: _f.color,
  );

  /// A centre panel of colours: the kind's own first, then the others.
  Future<void> _pickColor() async {
    final picked = await showPanel<int>(
      context,
      (context) => CenterPanel(
        glyph: Glyph.sparkle,
        color: accountHue(_preview),
        title: '卡片顏色',
        body: Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: WrapAlignment.center,
          children: [
            _Swatch(
              color: accountColor(_f.kind),
              label: '預設',
              picked: _f.color == null,
              onTap: () => Navigator.of(context).pop(-1),
            ),
            for (final c in Hue.categoryColors)
              _Swatch(
                color: shownColor(c),
                label: '顏色',
                picked: _f.color == c.toARGB32(),
                onTap: () => Navigator.of(context).pop(c.toARGB32()),
              ),
          ],
        ),
        actions: [PanelButton('取消', onTap: () => Navigator.of(context).pop())],
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _f.color = picked == -1 ? null : picked);
  }

  /// Every currency in a panel, for those not in the row.
  Future<void> _moreCurrencies() async {
    final picked = await pickOption<String>(
      context,
      title: '幣別',
      selected: _f.currency,
      options: [
        for (final code in Currency.supported)
          Option(code, code, Glyph.exchange, accountHue(_preview)),
      ],
    );
    if (picked != null && mounted) setState(() => _f.currency = picked);
  }

  Future<void> _moreIcons() async {
    final color = accountHue(_preview);
    final shown = _f.icon ?? kindIcon(_f.kind).name;
    final picked = await showSheet<String>(
      context,
      (context) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '選圖示',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            for (final (group, marks) in accountIconGroups) ...[
              Padding(
                padding: const EdgeInsets.only(top: 14, bottom: 6),
                child: Text(group, style: accentLabel),
              ),
              GridView.count(
                crossAxisCount: 4,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 1.1,
                children: [
                  for (final (key, name) in marks)
                    TapArea(
                      label: name,
                      selected: key == shown,
                      onTap: () => Navigator.of(context).pop(key),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _MarkCircle(
                            icon: iconFor(key),
                            color: color,
                            picked: key == shown,
                            size: 44,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            name,
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: Hue.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
    if (picked != null && mounted) setState(() => _f.icon = picked);
  }

  Future<void> _pickFund() async {
    final ledger = widget.ledger;
    final picked = await pickOption<String>(
      context,
      title: '撥款到',
      selected: _f.fundInto ?? '',
      columns: 3,
      options: [
        const Option('', '不入帳', Glyph.loan, Hue.investment),
        ...accountOptions(
          ledger,
          currency: homeCode,
          where: (a) => !a.kind.isDebt && a.kind != AccountKind.receivable,
        ),
      ],
    );
    if (picked == null || !mounted) return;
    setState(() => _f.fundInto = picked.isEmpty ? null : picked);
  }

  /// 刪除, 封存 or 恢復 when changing, and 儲存; what is left under it.
  Widget _buttons(Account? old) {
    final removable = old != null && !widget.ledger.isUsed(old.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 14),
        Row(
          children: [
            if (old != null)
              TextButton(
                onPressed: removable ? _remove : _archive,
                style: TextButton.styleFrom(
                  foregroundColor: removable || !old.archived
                      ? Hue.danger
                      : Hue.accent,
                  minimumSize: const Size(64, 46),
                ),
                child: Text(
                  removable
                      ? '刪除'
                      : old.archived
                      ? '恢復'
                      : widget.ledger.balance(old.id) == 0
                      ? '封存'
                      : '結清封存',
                ),
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
    );
  }

  /// 算進負債與淨資產, or 計入資產與淨資產, as a whole row.
  Widget get _counted {
    final label = _loanForm ? '算進負債與淨資產' : '計入資產與淨資產';
    return FormBlock(
      child: ToggleRow(
        value: _f.counted,
        onChanged: (on) => setState(() => _f.counted = on),
        label: label,
        child: Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
            TickSwitch(
              value: _f.counted,
              label: label,
              onChanged: (on) => setState(() => _f.counted = on),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final old = _old;
    final color = accountHue(_preview);
    final shownIcon = _f.icon ?? kindIcon(_f.kind).name;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _loanForm
            ? _loanFields(old)
            : [
                Text(
                  old == null ? '新增帳戶' : '編輯帳戶',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                _EditCard(
                  color: color,
                  icon: accountIcon(_preview),
                  kind: cardKindLabel(_preview),
                  name: _name,
                  balance: _balance,
                  balanceLabel: _f.kind.isDebt ? '目前欠款' : '目前餘額',
                  onColor: _pickColor,
                ),
                FormBlock(
                  title: '類型',
                  child: Row(
                    children: [
                      for (final (i, kind) in _kinds.indexed) ...[
                        if (i > 0) const SizedBox(width: 6),
                        Expanded(
                          child: ChoicePill(
                            label: switch (kind) {
                              AccountKind.bank => '銀行',
                              AccountKind.wallet => '支付',
                              _ => groupName(kind),
                            },
                            selected: kind == _f.kind,
                            background: Hue.white,
                            onTap: () => setState(() => _f.kind = kind),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                FormBlock(
                  title: '圖示',
                  child: Row(
                    children: [
                      for (final key in _usual)
                        Expanded(
                          child: _Mark(
                            icon: accountMark(key) ?? kindIcon(_f.kind),
                            name: accountIconName(key),
                            color: color,
                            picked: key == shownIcon,
                            onTap: () => setState(() => _f.icon = key),
                          ),
                        ),
                      Expanded(
                        child: TapArea(
                          label: '更多圖示',
                          onTap: _moreIcons,
                          child: Container(
                            width: 40,
                            height: 40,
                            alignment: Alignment.center,
                            decoration: const BoxDecoration(
                              color: Hue.white,
                              shape: BoxShape.circle,
                            ),
                            child: const Text(
                              '更多',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Hue.muted,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (old == null && _f.foreignAllowed)
                  FormBlock(
                    title: '幣別',
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final code in [
                            ..._common,
                            if (!_common.contains(_f.currency)) _f.currency,
                          ]) ...[
                            ChoicePill(
                              label: code == homeCode ? '台幣' : code,
                              selected: code == _f.currency,
                              background: Hue.white,
                              onTap: () => setState(() => _f.currency = code),
                            ),
                            const SizedBox(width: 6),
                          ],
                          ChoicePill(
                            label: '更多',
                            selected: false,
                            background: Hue.white,
                            onTap: _moreCurrencies,
                          ),
                        ],
                      ),
                    ),
                  ),
                if (_f.kind == AccountKind.card)
                  TileRow([
                    Tile(
                      icon: Glyph.calendar,
                      label: '結帳日',
                      value: '每月 ${_f.closing} 日',
                      size: 15,
                      onTap: () => _pickDay(true),
                    ),
                    Tile(
                      icon: Glyph.calendar,
                      label: '繳款日',
                      value: '每月 ${_f.due} 日',
                      size: 15,
                      onTap: () => _pickDay(false),
                    ),
                  ]),
                if (_f.kind == AccountKind.card)
                  FormBlock(
                    title: '信用額度',
                    child: _Field(controller: _limit, hint: '額度', number: true),
                  ),
                _counted,
                _buttons(old),
                if (old != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '目前 ${widget.ledger.moneyIn(widget.ledger.balance(old.id), old.currency)}',
                      textAlign: TextAlign.center,
                      style: mutedSmall,
                    ),
                  ),
              ],
      ),
    );
  }
}

/// The card on top of the form, and its first fields: the mark, the name
/// typed straight onto it and a dot of its colour that opens the
/// colours, over the balance.
class _EditCard extends StatelessWidget {
  const _EditCard({
    required this.color,
    required this.icon,
    required this.kind,
    required this.name,
    required this.balance,
    required this.balanceLabel,
    required this.onColor,
  });

  final Color color;
  final Glyph icon;
  final String kind;
  final TextEditingController name;
  final TextEditingController balance;
  final String balanceLabel;
  final VoidCallback onColor;

  @override
  Widget build(BuildContext context) {
    const plain = InputDecoration(
      isDense: true,
      border: InputBorder.none,
      contentPadding: EdgeInsets.symmetric(vertical: 6),
    );
    return Material(
      color: softOf(color),
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 8, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: const BoxDecoration(
                    color: Shade(0xC0FFFFFF, 0x1FFFFFFF),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: GlyphIcon(icon, size: 17, color: color),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: TextField(
                    controller: name,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                    decoration: plain.copyWith(
                      hintText: '帳戶名稱',
                      hintStyle: const TextStyle(color: Hue.faint),
                    ),
                  ),
                ),
                Text(kind, style: mutedSmall),
                Semantics(
                  button: true,
                  label: '卡片顏色',
                  excludeSemantics: true,
                  child: InkResponse(
                    onTap: onColor,
                    radius: 24,
                    child: SizedBox.square(
                      dimension: 48,
                      child: Center(
                        child: Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(color: Hue.white, width: 3),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Text(balanceLabel, style: mutedSmall),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: balance,
                    textAlign: TextAlign.end,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                    decoration: plain.copyWith(
                      hintText: '0',
                      hintStyle: const TextStyle(color: Hue.faint),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A round colour to pick, ringed when it is the one picked.
class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.label,
    required this.picked,
    required this.onTap,
  });

  final Color color;
  final String label;
  final bool picked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TapArea(
      label: label,
      selected: picked,
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: picked ? Hue.ink : Colors.transparent,
            width: 3,
          ),
        ),
        child: picked
            ? GlyphIcon(Glyph.check, size: 20, color: wordsOn(color))
            : null,
      ),
    );
  }
}

/// One of the marks offered on the form, named for a screen reader.
class _Mark extends StatelessWidget {
  const _Mark({
    required this.icon,
    required this.name,
    required this.color,
    required this.picked,
    required this.onTap,
  });

  final Glyph icon;
  final String name;
  final Color color;
  final bool picked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TapArea(
      label: '圖示：$name',
      selected: picked,
      onTap: onTap,
      child: _MarkCircle(icon: icon, color: color, picked: picked),
    );
  }
}

/// A mark on a white circle; the picked one on its kind's tint, ringed.
class _MarkCircle extends StatelessWidget {
  const _MarkCircle({
    required this.icon,
    required this.color,
    required this.picked,
    this.size = 40,
  });

  final Glyph icon;
  final Color color;
  final bool picked;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: picked ? softOf(color) : Hue.white,
        shape: BoxShape.circle,
        border: Border.all(
          color: picked ? color : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: GlyphIcon(
        icon,
        size: size * 0.5,
        color: picked ? color : Hue.muted,
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.hint,
    this.number = false,
  });

  final TextEditingController controller;
  final String hint;
  final bool number;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: number
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      decoration: InputDecoration(
        hintText: hint,
        isDense: true,
        filled: true,
        fillColor: Hue.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

/// A day of the month in the closing or due day picker: a 48 dp key
/// named for a screen reader.
class _DayKey extends StatelessWidget {
  const _DayKey({required this.day, required this.picked, required this.onTap});

  final int day;
  final bool picked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TapArea(
      label: '$day 日',
      selected: picked,
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: picked ? Hue.accent : Hue.tile,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          '$day',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: picked ? Hue.onAccent : Hue.ink,
          ),
        ),
      ),
    );
  }
}
