import 'package:flutter/material.dart';
import 'package:core/foundation_values.dart' show Currency;

import '../compose/pickers.dart';
import '../look/figures.dart';
import '../look/glyphs.dart';
import '../look/icons.dart';
import '../look/theme.dart';
import '../look/widgets.dart';
import '../model/ledger.dart';
import 'dialogs.dart';

/// True when [ledger] has an open account, after offering to add one if
/// it has none: entries, imports and recurring items all need one.
Future<bool> ensureAccount(BuildContext context, Ledger ledger) async {
  if (ledger.openAccounts.isNotEmpty) return true;
  final add = await confirm(context, '先新增一個帳戶，才能記帳', '新增帳戶');
  if (add && context.mounted) await editAccount(context, ledger);
  return ledger.openAccounts.isNotEmpty && context.mounted;
}

/// Opens the account form: a new account, or [account] to change. Saving
/// writes to [ledger] directly.
Future<void> editAccount(
  BuildContext context,
  Ledger ledger, {
  Account? account,
}) {
  return showSheet<void>(
    context,
    (_) => _AccountEditor(ledger: ledger, account: account),
  );
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
  late final _name = TextEditingController(text: _old?.name ?? '');
  late final _balance = TextEditingController(text: _startBalance());
  late final _limit = TextEditingController(text: '${_old?.limit ?? ''}');
  late var _kind = _old?.kind ?? AccountKind.bank;
  late String? _icon = _old?.icon;
  late var _closing = _old?.closingDay ?? 1;
  late var _due = _old?.dueDay ?? 15;
  late var _counted = _old?.inNetWorth ?? true;

  /// Chosen when the account is opened; fixed after that.
  late var _currency = _old?.currency ?? 'TWD';

  /// The currencies offered first; the rest open from 更多.
  static const _common = {'TWD', 'USD', 'JPY', 'EUR', 'CNY'};
  var _allCurrencies = false;

  String _startBalance() {
    final account = widget.account;
    if (account == null) return '';
    // A debt is shown as what is owed: a card at −500 reads 500, and one
    // overpaid by 300 reads −300.
    final balance = widget.ledger.balance(account.id);
    return plainIn(account.kind.isDebt ? -balance : balance, account.currency);
  }

  /// Cards and loans are kept in NT$.
  bool get _foreignAllowed => !_kind.isDebt;

  @override
  void dispose() {
    _name.dispose();
    _balance.dispose();
    _limit.dispose();
    super.dispose();
  }

  void _save() {
    final ledger = widget.ledger;
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final currency = _foreignAllowed ? _currency : 'TWD';
    final typed = minorOf(_balance.text, currency);
    final balance = typed == null ? null : (_kind.isDebt ? -typed : typed);
    final card = _kind == AccountKind.card;
    final old = _old;
    if (old == null) {
      ledger.addAccount(
        Account(
          ledger.newId(),
          name,
          _kind,
          balance ?? 0,
          icon: _icon,
          closingDay: card ? _closing : null,
          dueDay: card ? _due : null,
          limit: card ? int.tryParse(_limit.text.trim()) : null,
          inNetWorth: _counted,
          currency: currency,
        ),
      );
    } else {
      ledger.updateAccount(
        Account(
          old.id,
          name,
          _kind,
          old.opening,
          icon: _icon,
          closingDay: card ? _closing : null,
          dueDay: card ? _due : null,
          limit: card ? int.tryParse(_limit.text.trim()) : null,
          archived: old.archived,
          inNetWorth: _counted,
          currency: old.currency,
        ),
      );
      // A field left empty leaves the balance as it is.
      if (balance != null && balance != ledger.balance(old.id)) {
        ledger.setBalance(old.id, balance);
      }
    }
    Navigator.of(context).pop();
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
        options: [
          for (final a in ledger.openAccounts)
            if (a.id != old.id && !a.kind.isDebt && a.currency == old.currency)
              Option(a.id, a.name, accountIcon(a), accountColor(a.kind)),
        ],
      );
      if (into == null) return;
      ledger.add(
        Entry(
          id: ledger.newId(),
          date: ledger.today,
          type: EntryType.transfer,
          amount: left.abs(),
          account: left > 0 ? old.id : into,
          category: '轉帳',
          note: '${old.name}結清',
          to: left > 0 ? into : old.id,
        ),
      );
    }
    ledger.updateAccount(old.copyWith(archived: !old.archived));
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _remove() async {
    final old = _old;
    if (old == null) return;
    final ok = await confirm(context, '刪除「${old.name}」？', '刪除', danger: true);
    if (!ok || !mounted) return;
    widget.ledger.removeAccount(old.id);
    Navigator.of(context).pop();
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
                    picked: day == (closing ? _closing : _due),
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
        _closing = picked;
      } else {
        _due = picked;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final old = _old;
    final color = accountColor(_kind);
    final key = _icon;
    final icon = key == null ? kindIcon(_kind) : iconFor(key);
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
                        hint: _kind.isDebt ? '目前欠款' : '目前餘額',
                        number: true,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _Block(
            title: '類型',
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final kind in AccountKind.values)
                  _Choice(
                    label: groupName(kind),
                    picked: kind == _kind,
                    onTap: () => setState(() => _kind = kind),
                  ),
              ],
            ),
          ),
          _Block(
            title: '圖示',
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final key in accountIconKeys)
                  GestureDetector(
                    onTap: () => setState(() => _icon = key),
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: key == _icon ? Hue.white : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: key == _icon ? color : Colors.transparent,
                          width: 1.5,
                        ),
                      ),
                      child: GlyphIcon(
                        iconFor(key),
                        color: key == _icon ? color : Hue.muted,
                        tinted: key == _icon,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (old == null && _foreignAllowed)
            _Block(
              title: '幣別',
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final code in Currency.supported)
                    if (_allCurrencies ||
                        _common.contains(code) ||
                        code == _currency)
                      _Choice(
                        label: code,
                        picked: code == _currency,
                        onTap: () => setState(() => _currency = code),
                      ),
                  if (!_allCurrencies)
                    _Choice(
                      label: '更多…',
                      picked: false,
                      onTap: () => setState(() => _allCurrencies = true),
                    ),
                ],
              ),
            ),
          if (_kind == AccountKind.card)
            TileRow([
              Tile(
                icon: Glyph.calendar,
                label: '結帳日',
                value: '每月 $_closing 日',
                size: 15,
                onTap: () => _pickDay(true),
              ),
              Tile(
                icon: Glyph.calendar,
                label: '繳款日',
                value: '每月 $_due 日',
                size: 15,
                onTap: () => _pickDay(false),
              ),
            ]),
          if (_kind == AccountKind.card)
            _Block(
              title: '信用額度',
              child: _Field(controller: _limit, hint: '額度', number: true),
            ),
          _Block(
            child: Row(
              children: [
                const Expanded(
                  child: Text('計入資產與淨資產', style: TextStyle(fontSize: 14)),
                ),
                Switch(
                  value: _counted,
                  onChanged: (on) => setState(() => _counted = on),
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
                '目前 ${amountIn(widget.ledger.balance(old.id), old.currency)}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Hue.muted),
              ),
            ),
        ],
      ),
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({this.title, required this.child});

  final String? title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final head = title;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
      decoration: BoxDecoration(
        color: Hue.tile,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (head != null) ...[
            Text(
              head,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: Hue.accent,
              ),
            ),
            const SizedBox(height: 8),
          ],
          child,
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

class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.picked,
    required this.onTap,
  });

  final String label;
  final bool picked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: picked ? Hue.accent : Hue.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: picked ? Hue.white : Hue.accent,
          ),
        ),
      ),
    );
  }
}

class _DayKey extends StatelessWidget {
  const _DayKey({required this.day, required this.picked, required this.onTap});

  final int day;
  final bool picked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
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
            color: picked ? Hue.white : Hue.ink,
          ),
        ),
      ),
    );
  }
}
