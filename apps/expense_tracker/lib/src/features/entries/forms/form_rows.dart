import 'package:flutter/material.dart';

import '../../../core/ledger/ledger.dart';
import '../../../core/design_system/glyphs.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/design_system/spacing.dart';
import '../../../core/design_system/theme.dart';
import '../../../../design_system/display/amount.dart';
import '../../../core/widgets/icons.dart';
import '../model/compose_form.dart';
import 'choice_strip.dart';
import 'compose_actions.dart';
import 'compose_chips.dart';
import 'compose_widgets.dart';
import '../../../core/formatting/words.dart';

/// 常用 under the amount of a new entry: a spending or income used often,
/// or a transfer, to start from with one tap.
final class UsualFields {
  const UsualFields(this._a);

  final ComposeActions _a;

  ComposeForm get _f => _a.form;

  /// 常用: spending or income recorded alike again and again, each a tap
  /// away from a filled form, and, for spending, 掃發票 to fill it from a
  /// paper e-invoice; first of all 代墊 or 對方還錢, a switch to money paid
  /// for someone or paid back. On a new entry, 常用 stays once an amount
  /// is typed, so the form keeps its shape, and a tap still fills it all.
  Widget? spending() {
    final income = _f.mode == ComposeMode.income;
    if (_f.mode != ComposeMode.expense && !income) return null;
    final fresh = _a.fresh;
    final lend = !_a.viewing && !_f.foreign
        ? UsualChip(
            icon: Glyph.heart,
            name: income ? '對方還錢' : Words.lend,
            strong: true,
            onTap: income ? () => _a.lend(back: true) : _a.pickLent,
          )
        : null;
    final usual = fresh
        ? _f.ledger.entryQueryService.usual(income: income)
        : const <Entry>[];
    final scan = fresh && _a.canScan && !income;
    if (usual.isEmpty && !scan && lend == null) return null;
    return UsualRow(lead: lend, [
      if (scan) UsualChip(icon: Glyph.scan, name: '掃發票', onTap: _a.scanInvoice),
      for (final (e, category) in [
        for (final e in usual) (e, _f.ledger.category(e.category)),
      ])
        UsualChip(
          icon: iconFor(category.icon),
          name: e.merchant.isEmpty ? e.category : e.merchant,
          amount: groupDigits(e.amount),
          onTap: () => _a.update(() => _f.startFrom(e)),
        ),
    ]);
  }

  /// 常用轉帳: the same two accounts and amount moved again and again, a
  /// tap away; on a new transfer only, and kept once an amount is typed.
  Widget? transfers() {
    if (!_a.fresh) return null;
    final usual = _f.ledger.entryQueryService.usualTransfers();
    if (usual.isEmpty) return null;
    return UsualRow([
      for (final e in usual)
        UsualChip(
          icon: Glyph.transfer,
          name:
              '${_f.ledger.account(e.account).name}→'
              '${_f.ledger.account(e.to ?? e.account).name}',
          amount: groupDigits(e.amount),
          onTap: () => _a.update(() => _f.startTransferFrom(e)),
        ),
    ]);
  }
}

/// What an amount in another currency comes to: in NT$ for an entry, or
/// in the other end's currency for a transfer.
final class CurrencyFields {
  const CurrencyFields(this._a);

  final ComposeActions _a;

  ComposeForm get _f => _a.form;

  /// The worth in NT$ of a foreign amount, at today's rate until typed.
  Widget home() {
    final value = _f.homeValue;
    final rate = _f.ledger.marketData.rates[_f.currency];
    return Padding(
      padding: const EdgeInsets.only(top: Space.s2),
      child: FigureCard(
        color: _a.color,
        icon: Glyph.coins,
        label: '折合新台幣',
        value: value == null ? '請輸入' : groupDigits(value),
        valueColor: value == null ? AppColors.hint : AppColors.ink,
        size: TextSize.body,
        sub: _f.home != null || rate == null ? null : '臺銀即期買入 $rate',
        onTap: () async {
          final typed = await _a.ask('折合新台幣', value ?? 0);
          if (typed != null) _a.update(() => _f.home = typed);
        },
      ),
    );
  }

  /// What a transfer between currencies delivers, at today's rates until
  /// typed.
  Widget received() {
    final value = _f.receivedValue;
    return Padding(
      padding: const EdgeInsets.only(top: Space.s2),
      child: FigureCard(
        color: _a.color,
        icon: Glyph.coins,
        label: '轉入金額',
        value: value == null ? '請輸入' : amountIn(value, _f.toCurrency),
        valueColor: value == null ? AppColors.hint : AppColors.ink,
        size: TextSize.body,
        sub: _f.received == null && value != null ? '依臺銀即期匯率換算' : null,
        onTap: () async {
          final typed = await _a.ask('轉入金額', value ?? 0, unit: _f.toCurrency);
          if (typed != null) _a.update(() => _f.received = typed);
        },
      ),
    );
  }
}

/// The categories under the amount, and while splitting what is left of
/// it to share.
final class CategoryFields {
  const CategoryFields(this._a);

  final ComposeActions _a;

  ComposeForm get _f => _a.form;

  /// Under the amount of a split: whether the parts add up, and 平均分配.
  Widget splitState() {
    final parts = _f.parts ?? const [];
    final left = _f.splitLeft;
    return BubbleRow([
      Bubble(
        left == 0
            ? '✓ 剛好分完'
            : left > 0
            ? '還剩 ${groupDigits(left)}'
            : '多了 ${groupDigits(-left)}',
        null,
        color: left == 0 ? AppColors.positive.withValues(alpha: 0.14) : null,
        ink: left == 0 ? AppColors.positive : AppColors.negative,
      ),
      if (!_a.viewing && parts.isNotEmpty) Bubble('平均分配', _a.evenly),
    ]);
  }

  /// The categories as a row of marks that slides sideways, then 全部
  /// and 新增; 拆分 kept still at the right end. Grey until picked, then in
  /// the tab's colour; while splitting, each part in its category's own
  /// colour, and a tap adds a category as a part or takes it away.
  Widget row({required bool expense}) {
    final parts = _f.parts;
    final splitting = parts != null;
    final inParts = {for (final p in parts ?? const <(String, int)>[]) p.$1};
    final (:shown, :more) = _f.categoryRow();
    final lending = _f.mode == ComposeMode.lend;
    final items = [
      for (final category in [for (final n in shown) _f.ledger.category(n)])
        ChoiceStripItem(
          label: category.name,
          icon: iconFor(category.icon),
          color: splitting ? shownColor(Color(category.color)) : _a.color,
          picked: splitting
              ? inParts.contains(category.name)
              : !lending && category.name == _f.category,
          onTap: splitting
              ? () => _a.update(() => _f.togglePart(category.name))
              : () => _a.pickCategoryName(category.name),
        ),
      if (more)
        ChoiceStripItem(
          label: '全部',
          icon: Glyph.categories,
          color: _a.color,
          picked: false,
          onTap: splitting
              ? _a.addPart
              : () async {
                  final picked = await _a.pickCategory(_f.category);
                  if (picked != null) _a.pickCategoryName(picked);
                },
        ),
      if (!_a.viewing && !splitting)
        ChoiceStripItem(
          label: Words.add,
          icon: Glyph.add,
          color: _a.color,
          picked: false,
          onTap: () async {
            final made = await _a.newCategory();
            if (made != null) _a.pickCategoryName(made);
          },
        ),
    ];
    final canSplit =
        expense && !_a.viewing && !_f.foreign && !lending && !_f.lending;
    return ChoiceStrip(
      items: items,
      pinned: canSplit
          ? ChoiceStripItem(
              label: splitting ? '拆分中' : '拆分',
              icon: Glyph.sliders,
              color: AppColors.negative,
              solid: splitting,
              picked: false,
              onTap: _a.split,
            )
          : null,
    );
  }
}
