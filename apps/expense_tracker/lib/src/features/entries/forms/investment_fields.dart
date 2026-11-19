import 'package:flutter/material.dart';

import '../../../core/ledger/ledger.dart';
import '../../../core/design_system/glyphs.dart';
import '../../../core/design_system/spacing.dart';
import '../../../core/design_system/theme.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/formatting/dates.dart';
import '../../../core/formatting/figures.dart';
import '../../../core/widgets/calculator.dart';
import '../model/compose_form.dart';
import 'compose_actions.dart';
import 'compose_chips.dart';
import 'compose_widgets.dart';
import 'fields_fold.dart';
import 'note_field.dart';
import 'trade_cards.dart';
import '../../../core/formatting/words.dart';

/// What each [ShareChange] is called, in its order: 沒有, 配股, 分割, 減資.
const _shareChangeNames = ['沒有', '配股', '分割', '減資'];

/// The investment fields: a buy or sale from shares and price with the
/// broker's fee and tax, or a dividend with its premium and any change in
/// the shares held. They read and change the form through [ComposeActions].
final class InvestmentFields {
  const InvestmentFields(this._a);

  final ComposeActions _a;

  ComposeForm get _f => _a.form;

  /// The fields, in the order a trade is written down.
  List<Widget> build(BuildContext context) {
    final sell = _f.trade == EntryType.sell;
    const trades = [EntryType.buy, EntryType.sell, EntryType.dividend];
    // In the order a trade is written down: buy, sell or dividend; what it
    // comes to, large, where the other tabs have their amount; what, how
    // many at what price; when and from where; then the rest folded away.
    return [
      Padding(
        padding: const EdgeInsets.only(top: Space.s1),
        child: Segments(
          labels: const ['買進', '賣出', Words.dividend],
          selected: trades.indexOf(_f.trade),
          selectedColor: _a.color,
          onChanged: (i) => _a.changeTrade(trades[i]),
        ),
      ),
      if (_f.trading)
        AmountHero(
          label: sell ? '實收' : '應付',
          unit: sell ? '實收' : '應付',
          value: groupDigits(_f.settlement),
          color: _a.color,
          onTap: null,
        )
      else
        _a.hero(unit: Words.dividend),
      _codes(),
      if (_f.trading)
        _a.pair(
          TradeFigureCard(
            icon: Glyph.briefcase,
            label: '股數',
            value: groupDigits(_f.shares),
            current: _f.shares == 0,
            onTap: () async {
              final value = await _a.ask('股數', _f.shares, unit: '股');
              if (value != null) _a.update(() => _f.setShares(value));
            },
          ),
          TradeFigureCard(
            icon: Glyph.coins,
            label: '成交價',
            value: _f.price == _f.price.roundToDouble()
                ? '${_f.price.round()}'
                : _f.price.toStringAsFixed(2),
            current: _f.shares > 0 && _f.price == 0,
            onTap: () async {
              final value = await showPriceCalculator(
                context,
                title: '成交價',
                initial: _f.price,
                color: _a.color,
              );
              if (value != null) _a.update(() => _f.setPrice(value));
            },
          ),
        ),
      _a.pair(
        _a.accountPick(_f.trade == EntryType.buy ? '扣款帳戶' : '入帳帳戶'),
        _a.datePick(),
      ),
      if (_f.trading) _tradeFold() else _dividendFold(),
    ];
  }

  /// A trade's sums, what a sale made and the note, folded away: closed,
  /// the heading says the fee, tax and how cost is reckoned.
  Widget _tradeFold() {
    final (fee, tax) = _f.charges;
    final suggested = _f.suggested;
    final sell = _f.trade == EntryType.sell;
    final settles = _f.settlement;
    final cost = _f.saleCost;
    final settled = _f.settles;
    final method = _f.average ? '平均成本' : '先進先出';
    return FieldsFold(
      viewing: _a.viewing,
      onToggle: () => _a.update(() => _f.more = !_f.more),
      closed: [
        '手續費 ${groupDigits(fee)}',
        if (sell) '證交稅 ${groupDigits(tax)}',
        if (sell) method,
        if (_a.note.text.trim().isNotEmpty) _a.note.text.trim(),
      ].join(' · '),
      open: _f.more || _a.viewing,
      body: [
        // What it settles at, as a sum: the trade, then the fee and tax
        // taken off a sale or added to a buy; the charges can be changed.
        SettlementRow(
          sell: sell,
          amount: _f.amount,
          fee: fee,
          suggestedFee: suggested.$1,
          tax: tax,
          suggestedTax: suggested.$2,
          onAmount: _a.viewing ? null : _a.calculate,
          onFee: _a.viewing
              ? null
              : () => _change(Words.fee, fee, (v) => _f.tradeFee = v),
          onTax: _a.viewing
              ? null
              : () => _change('證交稅', tax, (v) => _f.tradeTax = v),
        ),
        if (sell && !_a.viewing) _costMethod(),
        if (_f.amount > 0)
          Padding(
            padding: const EdgeInsets.only(top: Space.s2),
            child: TradeOutcomeCard(
              title: cost == null ? '交割' : '已實現損益',
              sub: cost == null
                  ? formatMd(settled)
                  : '成本 ${groupDigits(cost)} · 交割 ${formatMd(settled)}',
              value: cost == null ? null : signed(settles - cost),
              color: cost == null || settles >= cost
                  ? Hue.positive
                  : Hue.negative,
            ),
          ),
        NoteField(controller: _a.note, viewing: _a.viewing, lines: 2),
      ],
    );
  }

  /// 成本算法 for a sale: first in, first out, or the average.
  Widget _costMethod() => Padding(
    padding: const EdgeInsets.only(top: Space.s2),
    child: Row(
      children: [
        const Padding(
          padding: EdgeInsets.only(left: Space.s1, right: Space.s2),
          child: Text(
            '成本算法',
            style: TextStyle(
              fontSize: TextSize.caption,
              fontWeight: FontWeight.w700,
              color: Hue.muted,
            ),
          ),
        ),
        Expanded(
          child: Segments(
            labels: const ['先進先出', '平均成本'],
            selected: _f.average ? 1 : 0,
            selectedColor: _a.color,
            onChanged: (i) => _a.update(() => _f.average = i == 1),
          ),
        ),
      ],
    ),
  );

  /// A dividend's change in shares, its premium and the note, folded
  /// away.
  Widget _dividendFold() {
    final change = _f.shareChangeKind;
    final filled = [
      if (_f.shareChange)
        '${_shareChangeNames[change.index]} ${groupDigits(_f.shares)} 股',
      if (_f.withheld > 0) '二代健保 ${groupDigits(_f.withheld)}',
      if (_a.note.text.trim().isNotEmpty) _a.note.text.trim(),
    ];
    return FieldsFold(
      viewing: _a.viewing,
      onToggle: () => _a.update(() => _f.more = !_f.more),
      closed: filled.isEmpty ? '配股、二代健保、備註' : filled.join(' · '),
      open: _f.more || _a.viewing,
      body: [
        if (!_a.viewing || _f.shareChange) ...[
          const GroupLabel('股數有變動'),
          Segments(
            labels: _shareChangeNames,
            selected: change.index,
            selectedColor: _a.color,
            onChanged: (i) =>
                _a.update(() => _f.setShareChange(ShareChange.values[i])),
          ),
        ],
        Padding(
          padding: const EdgeInsets.only(top: Space.s2),
          child: Row(
            children: [
              if (_f.shareChange) ...[
                Expanded(
                  child: SettlementBox(
                    '${_shareChangeNames[change.index]}'
                        '${change == ShareChange.capitalReduction ? '減少' : '增加'}',
                    '${groupDigits(_f.shares)} 股',
                    _a.viewing
                        ? null
                        : () async {
                            final value = await _a.ask(
                              _f.reduce ? '減少股數' : '增加股數',
                              _f.shares,
                              unit: '股',
                            );
                            if (value != null) {
                              _a.update(() => _f.shares = value);
                            }
                          },
                  ),
                ),
                const SizedBox(width: Space.s2),
              ],
              if (!_f.reducing)
                Expanded(
                  child: SettlementBox(
                    '二代健保',
                    groupDigits(_f.withheld),
                    _a.viewing
                        ? null
                        : () async {
                            final value = await _a.ask('二代健保補充保費', _f.withheld);
                            if (value != null) {
                              _a.update(() => _f.premium = value);
                            }
                          },
                  ),
                ),
            ],
          ),
        ),
        if (!_a.viewing && !_f.reducing)
          const Padding(
            padding: EdgeInsets.fromLTRB(Space.s1, Space.s2, Space.s1, 0),
            child: Text('單筆股息 2 萬以上才扣二代健保，會自動算', style: mutedSmall),
          ),
        NoteField(controller: _a.note, viewing: _a.viewing, lines: 2),
      ],
    );
  }

  /// The holdings as one row of pills, and the square that opens them all.
  Widget _codes() => HoldingCodeRow(
    holdings: _f.ledger.holdings.all,
    picked: _f.holding,
    onPick: (code) => _a.update(() => _f.holding = code),
    onAll: _a.pickHolding,
  );

  /// Asks for a charge of the trade, [label] now [value], and keeps
  /// what is typed.
  Future<void> _change(
    String label,
    int value,
    void Function(int value) keep,
  ) async {
    final typed = await _a.ask(label, value);
    if (typed != null) _a.update(() => keep(typed));
  }
}
