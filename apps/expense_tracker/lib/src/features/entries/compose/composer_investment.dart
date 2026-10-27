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
    // In the order a trade is written down: what, how many at what price,
    // when and from where; then what it settles at, and what it made.
    return [
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Tile(
          icon: Glyph.investment,
          label: '標的',
          value: code == null
              ? '選擇標的'
              : held == null
              ? code
              : holdingLabel(held),
          size: 15,
          sub: held == null
              ? null
              : '持有 ${_ledger.orDots(groupDigits(held.shares))} 股',
          trailing: _viewing
              ? null
              : TapArea(
                  label: '新增標的',
                  onTap: _newHolding,
                  child: const GlyphIcon(Glyph.add, size: 18),
                ),
          onTap: _pickHolding,
        ),
      ),
      if (_f.trading)
        TileRow([
          Tile(
            icon: Glyph.briefcase,
            label: '股數',
            value: groupDigits(_f.shares),
            onTap: () async {
              final value = await _ask('股數', _f.shares, unit: '股');
              if (value != null) _set(() => _f.setShares(value));
            },
          ),
          Tile(
            icon: Glyph.coins,
            label: '成交價',
            value: _f.price == _f.price.roundToDouble()
                ? '${_f.price.round()}'
                : _f.price.toStringAsFixed(2),
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
        ]),
      if (_f.trade == EntryType.dividend && !_f.shareChange && !_viewing)
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
      if (_f.trade == EntryType.dividend) ...[
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
      TileRow([
        _dateTile(),
        _accountTile(_f.trade == EntryType.buy ? '扣款帳戶' : '入帳帳戶'),
      ]),
      if (_f.trading)
        FormBlock(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Line(
                sell ? '實收' : '應付',
                groupDigits(settles),
                strong: true,
                color: _color,
              ),
              const Divider(height: 8),
              // Typed here, the amount sets the price for the shares.
              _Line(
                '成交金額',
                groupDigits(_f.amount),
                onTap: _viewing ? null : _calculate,
              ),
              _chargeLine('手續費', fee, suggested.$1, (v) => _f.tradeFee = v),
              if (sell)
                _chargeLine('證交稅', tax, suggested.$2, (v) => _f.tradeTax = v),
            ],
          ),
        ),
      if (_f.trading && sell && !_viewing)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Segments(
            labels: const ['先進先出', '平均成本'],
            selected: _f.average ? 1 : 0,
            onChanged: (i) => _set(() => _f.average = i == 1),
          ),
        ),
      if (_f.trading && (cost != null || _f.amount > 0))
        FormBlock(
          child: Column(
            children: [
              if (cost != null && _f.amount > 0)
                _Line(
                  '已實現損益',
                  signed(settles - cost),
                  color: settles < cost ? Hue.negative : Hue.positive,
                ),
              _Line('交割日', '${settled.month}/${settled.day}'),
            ],
          ),
        ),
      _noteField(),
    ];
  }

  /// A trade's fee or tax as a line of the settlement: what the broker
  /// charged, typed in, or the suggestion until then.
  Widget _chargeLine(
    String label,
    int value,
    int suggested,
    void Function(int value) keep,
  ) {
    return _Line(
      value == suggested ? '$label（試算）' : label,
      groupDigits(value),
      color: value > 0 ? Hue.negative : Hue.ink,
      onTap: _viewing
          ? null
          : () async {
              final typed = await _ask(label, value);
              if (typed != null) _set(() => keep(typed));
            },
    );
  }
}
