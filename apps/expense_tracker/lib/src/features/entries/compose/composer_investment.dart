part of 'composer.dart';

/// The investment fields: a buy or sale from shares and price with the
/// broker's fee and tax, or a dividend with its premium and any change in
/// the shares held.
extension _InvestmentFields on _ComposerState {
  List<Widget> _investmentFields() {
    final code = _f.holding;
    final held = code == null ? null : _ledger.holding(code);
    final (fee, tax) = _f.charges;
    final suggested = _f.suggested;
    final sell = _f.trade == EntryType.sell;
    final cost =
        sell && code != null && held != null && _f.shares <= held.shares
        ? _ledger.saleCost(code, _f.shares, average: _f.average)
        : null;
    final settled = settlementDay(_f.date);
    final settles = _f.settlement;
    // In the order a trade is written down: buy or sell, what, how many
    // at what price and what that settles at; when and from where; then
    // what it made.
    return [
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: _TradeChips(
          trade: _f.trade,
          locked: _viewing,
          onChanged: _changeTrade,
        ),
      ),
      _holdings(),
      if (_f.trading) ...[
        _pair(
          _Figure(
            icon: Glyph.briefcase,
            label: '股數',
            value: groupDigits(_f.shares),
            current: _f.shares == 0,
            onTap: () async {
              final value = await _ask('股數', _f.shares, unit: '股');
              if (value != null) _set(() => _f.setShares(value));
            },
          ),
          _Figure(
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
        // What the trade settles at: the sums it is made of on the left,
        // each opened with a tap, and the total on the right.
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 10,
                  children: [
                    // Typed here, the amount sets the price for the shares.
                    _EditWords(
                      '成交 ${groupDigits(_f.amount)}',
                      _viewing ? null : _calculate,
                    ),
                    _chargeWords('手續費', fee, suggested.$1, (v) {
                      _f.tradeFee = v;
                    }),
                    if (sell)
                      _chargeWords('證交稅', tax, suggested.$2, (v) {
                        _f.tradeTax = v;
                      }),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    sell ? '實收' : '應付',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: Hue.muted,
                    ),
                  ),
                  Text(
                    groupDigits(settles),
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                      color: _color,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
      if (_f.trade == EntryType.dividend) ...[
        _hero(),
        if (!_f.shareChange && !_viewing)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: SmallLink(
                '＋ 配股、分割或減資',
                () => _set(() => _f.shareChange = true),
                inset: 6,
              ),
            ),
          ),
        if (_f.shareChange)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Tile(
              icon: Glyph.briefcase,
              label: _f.reducing
                  ? '減資減少股數'
                  : _f.splitShares
                  ? '分割增加股數'
                  : '配股股數',
              value: groupDigits(_f.shares),
              size: 15,
              onTap: () async {
                final value = await _ask(
                  _f.reduce ? '減少股數' : '增加股數',
                  _f.shares,
                  unit: '股',
                );
                if (value != null) _set(() => _f.shares = value);
              },
            ),
          ),
        // The premium only applies from NT$20,000 a payment; below that
        // there is nothing to show unless one was typed.
        if (_f.amount > 0 &&
            !_f.reducing &&
            (_f.withheld > 0 || _f.premium != null))
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Tile(
              icon: Glyph.coins,
              label: '二代健保補充保費',
              value: groupDigits(_f.withheld),
              valueColor: _f.withheld > 0 ? Hue.negative : Hue.ink,
              size: 15,
              sub: '實收 ${groupDigits(_f.amount - _f.withheld)}',
              onTap: () async {
                final value = await _ask('二代健保補充保費', _f.withheld);
                if (value != null) _set(() => _f.premium = value);
              },
            ),
          ),
        if (_f.shares > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Segments(
              labels: const ['配股', '分割', '減資'],
              selected: _f.reduce
                  ? 2
                  : _f.splitShares
                  ? 1
                  : 0,
              onChanged: (i) => _set(() {
                _f.splitShares = i == 1;
                _f.reduce = i == 2;
              }),
            ),
          ),
      ],
      _pair(
        _accountPick(_f.trade == EntryType.buy ? '扣款帳戶' : '入帳帳戶'),
        _datePick(),
      ),
      // How a sale's cost is reckoned, what it made and when it settles:
      // one line under the accounts.
      if (_f.trading && ((sell && !_viewing) || _f.amount > 0))
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
          child: Row(
            children: [
              if (sell && !_viewing)
                _MiniSegments(
                  labels: const ['先進先出', '平均成本'],
                  selected: _f.average ? 1 : 0,
                  onChanged: (i) => _set(() => _f.average = i == 1),
                ),
              const Spacer(),
              if (_f.amount > 0)
                Flexible(
                  flex: 3,
                  child: Text.rich(
                    TextSpan(
                      children: [
                        if (cost != null) ...[
                          const TextSpan(text: '已實現 '),
                          TextSpan(
                            text: signed(settles - cost),
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: settles < cost
                                  ? Hue.negative
                                  : Hue.positive,
                            ),
                          ),
                          const TextSpan(text: ' · '),
                        ],
                        TextSpan(text: '交割 ${settled.month}/${settled.day}'),
                      ],
                    ),
                    textAlign: TextAlign.end,
                    style: mutedSmall,
                  ),
                ),
            ],
          ),
        ),
      _noteRow(),
    ];
  }

  /// The holdings as a row of their codes that slides sideways, those
  /// held first, then 新增; 全部 kept still at the right end.
  Widget _holdings() {
    final code = _f.holding;
    final holdings = _ledger.holdings;
    final known = {for (final h in holdings) h.code};
    return _Strip(
      items: [
        if (code != null && !known.contains(code))
          _StripItem(
            label: code,
            code: code,
            color: _codeColor(code),
            picked: true,
            ring: Hue.investment,
            onTap: () {},
          ),
        for (final h in holdings)
          _StripItem(
            label: h.name.isEmpty ? h.code : h.name,
            code: h.code,
            color: _codeColor(h.code),
            picked: h.code == code,
            ring: Hue.investment,
            onTap: () => _set(() => _f.holding = h.code),
          ),
        if (!_viewing)
          _StripItem(
            label: '新增',
            icon: Glyph.add,
            color: Hue.accent,
            picked: false,
            onTap: _newHolding,
          ),
      ],
      pinned: _StripItem(
        label: '全部',
        icon: Glyph.investment,
        color: Hue.muted,
        picked: false,
        onTap: _pickHolding,
      ),
    );
  }

  /// A trade's fee or tax among the sums it settles at: what the broker
  /// charged, typed in, or the suggestion until then (試算).
  Widget _chargeWords(
    String label,
    int value,
    int suggested,
    void Function(int value) keep,
  ) {
    return _EditWords(
      '${value == suggested ? '$label（試算）' : label} ${groupDigits(value)}',
      _viewing
          ? null
          : () async {
              final typed = await _ask(label, value);
              if (typed != null) _set(() => keep(typed));
            },
    );
  }
}
