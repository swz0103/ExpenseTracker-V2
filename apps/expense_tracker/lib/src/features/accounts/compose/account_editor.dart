import 'package:core/foundation_values.dart' show Currency;
import 'package:flutter/material.dart';

import '../../../core/look/dialogs.dart';
import '../../../core/look/figures.dart';
import '../../../core/look/glyphs.dart';
import '../../../core/look/icons.dart';
import '../../../core/look/theme.dart';
import '../../../core/look/widgets.dart';
import '../../../core/ledger/ledger.dart';
import '../../../core/ui/pickers.dart';
import '../model/account_form.dart';

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

class _AccountEditor extends StatefulWidget {
  const _AccountEditor({required this.ledger, this.account});

  final Ledger ledger;
  final Account? account;

  @override
  State<_AccountEditor> createState() => _AccountEditorState();
}

class _AccountEditorState extends State<_AccountEditor> {
  late final _old = widget.account;

  /// The fields and what saving does.
  late final _f = AccountForm(widget.ledger, old: _old);
  late final TextEditingController _name = TextEditingController(text: _f.name)
    ..addListener(() => _f.name = _name.text);
  late final TextEditingController _balance = TextEditingController(
    text: _f.balance,
  )..addListener(() => _f.balance = _balance.text);
  late final TextEditingController _limit = TextEditingController(
    text: _f.limit,
  )..addListener(() => _f.limit = _limit.text);

  /// The currencies offered first; the rest open from 更多.
  static const _common = {homeCode, 'USD', 'JPY', 'EUR', 'CNY'};
  var _allCurrencies = false;

  @override
  void dispose() {
    _name.dispose();
    _balance.dispose();
    _limit.dispose();
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

  @override
  Widget build(BuildContext context) {
    final old = _old;
    final color = accountColor(_f.kind);
    final key = _f.icon;
    final icon = key == null ? kindIcon(_f.kind) : iconFor(key);
    final removable = old != null && !widget.ledger.isUsed(old.id);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            old == null ? '新增帳戶' : '編輯帳戶',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Hue.hero,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Row(
              children: [
                IconBadge(icon, color, size: 46),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    children: [
                      _Field(controller: _name, hint: '帳戶名稱'),
                      const SizedBox(height: 8),
                      _Field(
                        controller: _balance,
                        hint: _f.kind.isDebt ? '目前欠款' : '目前餘額',
                        number: true,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          FormBlock(
            title: '類型',
            child: Wrap(
              spacing: 6,
              children: [
                for (final kind in AccountKind.values)
                  ChoicePill(
                    label: groupName(kind),
                    selected: kind == _f.kind,
                    background: Hue.white,
                    onTap: () => setState(() => _f.kind = kind),
                  ),
              ],
            ),
          ),
          FormBlock(
            title: '圖示',
            child: Wrap(
              spacing: 0,
              runSpacing: 0,
              children: [
                for (final (key, name) in accountIcons)
                  TapArea(
                    label: '圖示：$name',
                    selected: key == _f.icon,
                    onTap: () => setState(() => _f.icon = key),
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: key == _f.icon ? Hue.white : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: key == _f.icon ? color : Colors.transparent,
                          width: 1.5,
                        ),
                      ),
                      child: GlyphIcon(
                        iconFor(key),
                        color: key == _f.icon ? color : Hue.muted,
                        tinted: key == _f.icon,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (old == null && _f.foreignAllowed)
            FormBlock(
              title: '幣別',
              child: Wrap(
                spacing: 6,
                children: [
                  for (final code in Currency.supported)
                    if (_allCurrencies ||
                        _common.contains(code) ||
                        code == _f.currency)
                      ChoicePill(
                        label: code,
                        selected: code == _f.currency,
                        background: Hue.white,
                        onTap: () => setState(() => _f.currency = code),
                      ),
                  if (!_allCurrencies)
                    ChoicePill(
                      label: '更多…',
                      selected: false,
                      background: Hue.white,
                      onTap: () => setState(() => _allCurrencies = true),
                    ),
                ],
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
          FormBlock(
            child: Row(
              children: [
                const Expanded(
                  child: Text('計入資產與淨資產', style: TextStyle(fontSize: 14)),
                ),
                Switch(
                  value: _f.counted,
                  onChanged: (on) => setState(() => _f.counted = on),
                ),
              ],
            ),
          ),
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
