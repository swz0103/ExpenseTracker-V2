part of 'composer.dart';

/// The investment fields: a buy or sale from shares and price with the
/// broker's fee and tax, or a dividend with its premium and any change in
/// the shares held.
/// What each [ShareChange] is called, in its order: 沒有, 配股, 分割, 減資.
const _shareChangeNames = ['沒有', '配股', '分割', '減資'];

extension _InvestmentFields on _ComposerState {
  List<Widget> _investmentFields() {
    final sell = _f.trade == EntryType.sell;
    const trades = [EntryType.buy, EntryType.sell, EntryType.dividend];
    // In the order a trade is written down: buy, sell or dividend; what it
    // comes to, large, where the other tabs have their amount; what, how
    // many at what price; when and from where; then the rest folded away.
    return [
      Padding(
        padding: const EdgeInsets.only(top: Space.s1),
        child: Segments(
          labels: const ['買進', '賣出', '股息'],
          selected: trades.indexOf(_f.trade),
          selectedColor: _color,
          onChanged: (i) => _changeTrade(trades[i]),
        ),
      ),
      if (_f.trading)
        AmountHero(
          label: sell ? '實收' : '應付',
          unit: sell ? '實收' : '應付',
          value: groupDigits(_f.settlement),
          color: _color,
          onTap: null,
        )
      else
        _hero(unit: '股息'),
      _codes(),
      if (_f.trading)
        _pair(
          TradeFigureCard(
            icon: Glyph.briefcase,
            label: '股數',
            value: groupDigits(_f.shares),
            current: _f.shares == 0,
            onTap: () async {
              final value = await _ask('股數', _f.shares, unit: '股');
              if (value != null) _set(() => _f.setShares(value));
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
                color: _color,
              );
              if (value != null) _set(() => _f.setPrice(value));
            },
          ),
        ),
      _pair(
        _accountPick(_f.trade == EntryType.buy ? '扣款帳戶' : '入帳帳戶'),
        _datePick(),
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
    return _fold(
      closed: [
        '手續費 ${groupDigits(fee)}',
        if (sell) '證交稅 ${groupDigits(tax)}',
        if (sell) method,
        if (_note.text.trim().isNotEmpty) _note.text.trim(),
      ].join(' · '),
      open: _f.more || _viewing,
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
          onAmount: _viewing ? null : _calculate,
          onFee: _viewing
              ? null
              : () => _change('手續費', fee, (v) => _f.tradeFee = v),
          onTax: _viewing
              ? null
              : () => _change('證交稅', tax, (v) => _f.tradeTax = v),
        ),
        if (sell && !_viewing)
          Padding(
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
                    selectedColor: _color,
                    onChanged: (i) => _set(() => _f.average = i == 1),
                  ),
                ),
              ],
            ),
          ),
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
        _noteField(lines: 2),
      ],
    );
  }

  /// A dividend's change in shares, its premium and the note, folded
  /// away.
  Widget _dividendFold() {
    final change = _f.shareChangeKind;
    final filled = [
      if (_f.shareChange)
        '${_shareChangeNames[change.index]} ${groupDigits(_f.shares)} 股',
      if (_f.withheld > 0) '二代健保 ${groupDigits(_f.withheld)}',
      if (_note.text.trim().isNotEmpty) _note.text.trim(),
    ];
    return _fold(
      closed: filled.isEmpty ? '配股、二代健保、備註' : filled.join(' · '),
      open: _f.more || _viewing,
      body: [
        if (!_viewing || _f.shareChange) ...[
          const GroupLabel('股數有變動'),
          Segments(
            labels: _shareChangeNames,
            selected: change.index,
            selectedColor: _color,
            onChanged: (i) =>
                _set(() => _f.setShareChange(ShareChange.values[i])),
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
                    _viewing
                        ? null
                        : () async {
                            final value = await _ask(
                              _f.reduce ? '減少股數' : '增加股數',
                              _f.shares,
                              unit: '股',
                            );
                            if (value != null) _set(() => _f.shares = value);
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
                    _viewing
                        ? null
                        : () async {
                            final value = await _ask('二代健保補充保費', _f.withheld);
                            if (value != null) _set(() => _f.premium = value);
                          },
                  ),
                ),
            ],
          ),
        ),
        if (!_viewing && !_f.reducing)
          const Padding(
            padding: EdgeInsets.fromLTRB(Space.s1, Space.s2, Space.s1, 0),
            child: Text('單筆股息 2 萬以上才扣二代健保，會自動算', style: mutedSmall),
          ),
        _noteField(lines: 2),
      ],
    );
  }

  /// The holdings as one row of pills, and the square that opens them all.
  Widget _codes() => HoldingCodeRow(
    holdings: _ledger.holdings.all,
    picked: _f.holding,
    onPick: (code) => _set(() => _f.holding = code),
    onAll: _pickHolding,
  );

  /// Asks for a charge of the trade, [label] now [value], and keeps
  /// what is typed.
  Future<void> _change(
    String label,
    int value,
    void Function(int value) keep,
  ) async {
    final typed = await _ask(label, value);
    if (typed != null) _set(() => keep(typed));
  }
}
