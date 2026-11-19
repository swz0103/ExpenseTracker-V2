import 'package:flutter/material.dart';

import '../../../core/design_system/glyphs.dart';
import '../../../core/design_system/theme.dart';
import '../../../core/formatting/figures.dart';
import '../../../core/widgets/shown_amounts.dart';
import '../model/compose_form.dart';
import 'compose_actions.dart';
import 'compose_chips.dart';
import 'extras_fields.dart';

/// The 代墊 fields: whom the money is for or from, and the person's own
/// account that keeps what they owe, read and changed through
/// [ComposeActions].
final class LendFields {
  const LendFields(this._a);

  final ComposeActions _a;

  ComposeForm get _f => _a.form;

  /// 代墊 under 支出 (paid for someone) or 對方還錢 under 收入. Each
  /// person has an account of their own that keeps what they owe. Paid
  /// back, the sums they owe stand in place of the categories, to tick
  /// those being paid.
  List<Widget> build() {
    final person = _f.to.isEmpty ? null : _f.ledger.account(_f.to);
    final owed = _f.owedNow;
    final name = person?.name ?? '新增對象';
    final String sub;
    if (person == null) {
      sub = '';
    } else if (_f.back) {
      final left = owed - _f.amount;
      sub = left <= 0 ? '· 還完不欠' : '· 還完欠 ${_f.ledger.money(left)}';
    } else {
      sub = owed == 0 ? '· 目前沒有欠' : '· 目前欠 ${_f.ledger.money(owed)}';
    }
    return [
      _a.hero(
        under: PersonPill(
          text: _f.back ? '$name 還錢' : '幫 $name 付',
          sub: sub,
          color: _a.color,
          onTap: _a.pickPerson,
          onClear: _a.viewing || _a.editing ? null : _a.unlend,
        ),
      ),
      if (_f.back) _owedCards() else _a.categories(expense: true),
      _a.pair(_a.accountPick(_f.back ? '收款帳戶' : '付款帳戶'), _a.datePick()),
      ExtrasFields(_a).build(expense: false),
    ];
  }

  /// Under the amount of a spending paid partly for others, in place of
  /// 常用: one's own share, then each person's, a tap to change it, ＋ for
  /// more people and a cross back to one's own spending.
  Widget row() {
    final shares = _f.lent ?? const <(String, int)>[];
    return UsualRow(
      lead: UsualChip(
        icon: Glyph.wallet,
        name: '自己',
        amount: groupDigits(_f.own),
        onTap: _a.calculate,
      ),
      [
        for (final (i, (person, value)) in shares.indexed)
          LentShareChip(
            name: _f.ledger.account(person).name,
            amount: groupDigits(value),
            color: AppColors.receivable,
            onTap: _a.viewing
                ? null
                : () async {
                    final name = _f.ledger.account(person).name;
                    final typed = await _a.ask('幫$name付', value);
                    if (typed != null) _a.update(() => _f.setLent(i, typed));
                  },
          ),
        if (!_a.viewing) ...[
          UsualChip(icon: Glyph.add, name: '代墊給…', onTap: _a.pickLent),
          IconButton(
            tooltip: '不代墊',
            onPressed: () => _a.update(_f.stopLending),
            icon: const GlyphIcon(
              Glyph.close,
              size: 16,
              color: AppColors.faint,
            ),
          ),
        ],
      ],
    );
  }

  /// What the person still owes, sum by sum, as cards to tick in a row;
  /// nothing while only looked at.
  Widget _owedCards() => _a.viewing
      ? const SizedBox.shrink()
      : OwedCardRow(
          sums: _f.owedSums,
          titleOf: _f.owedTitle,
          paying: _f.paying,
          color: _a.color,
          onToggle: (id) => _a.update(() => _f.togglePaying(id)),
        );
}
