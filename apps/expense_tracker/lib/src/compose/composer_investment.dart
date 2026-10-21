part of 'composer.dart';

/// The investment fields: a buy or sale from shares and price with the
/// broker's fee and tax, or a dividend with its premium and any change in
/// the shares held.
extension _InvestmentFields on _ComposerState {
  List<Widget> _investmentFields() {
    final code = _holding;
    final held = code == null ? null : _ledger.holding(code);
    final (fee, tax) = _charges;
    final suggested = _suggested;
    final sell = _trade == EntryType.sell;
    final cost = sell && code != null && held != null && _shares <= held.shares
        ? _ledger.saleCost(code, _shares, average: _average)
        : null;
    final settled = settlementDay(_date);
    return [
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Tile(
          icon: Glyph.investment,
          label: '標的',
          value: code == null ? '選擇標的' : '$code ${held?.name ?? ''}',
          size: 15,
          sub: held == null ? null : '持有 ${_ledger.orDots(groupDigits(held.shares))} 股',
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
      if (_trading)
        TileRow([
          Tile(
            icon: Glyph.briefcase,
            label: '股數',
            value: groupDigits(_shares),
            onTap: () async {
              final value = await _ask('股數', _shares, unit: '股');
              if (value == null) return;
              _set(() {
                _shares = value;
                _amount = (_shares * _price).round();
              });
            },
          ),
          Tile(
            icon: Glyph.coins,
            label: '成交價',
            value: _price == _price.roundToDouble()
                ? '${_price.round()}'
                : _price.toStringAsFixed(2),
            onTap: () async {
              final value = await showPriceCalculator(
                context,
                title: '成交價',
                initial: _price,
                color: _color,
              );
              if (value == null) return;
              _set(() {
                _price = value;
                _amount = (_shares * _price).round();
              });
            },
          ),
        ]),
      if (_trade == EntryType.dividend && !_shareChange && !_viewing)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SmallLink(
              '＋ 配股、分割或減資',
              () => _set(() => _shareChange = true),
              inset: 6,
            ),
          ),
        ),
      if (_trade == EntryType.dividend) ...[
        if (_shareChange)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Tile(
              icon: Glyph.briefcase,
              label: _reducing
                  ? '減資減少股數'
                  : _splitShares
                  ? '分割增加股數'
                  : '配股股數',
              value: groupDigits(_shares),
              size: 15,
              onTap: () async {
                final value = await _ask(
                  _reduce ? '減少股數' : '增加股數',
                  _shares,
                  unit: '股',
                );
                if (value != null) _set(() => _shares = value);
              },
            ),
          ),
        // The premium only applies from NT$20,000 a payment; below that
        // there is nothing to show unless one was typed.
        if (_amount > 0 && !_reducing && (_withheld > 0 || _premium != null))
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Tile(
              icon: Glyph.coins,
              label: '二代健保補充保費',
              value: groupDigits(_withheld),
              valueColor: _withheld > 0 ? Hue.negative : Hue.ink,
              size: 15,
              sub: '實收 ${groupDigits(_amount - _withheld)}',
              onTap: () async {
                final value = await _ask('二代健保補充保費', _withheld);
                if (value != null) _set(() => _premium = value);
              },
            ),
          ),
        if (_shares > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Segments(
              labels: const ['配股', '分割', '減資'],
              selected: _reduce
                  ? 2
                  : _splitShares
                  ? 1
                  : 0,
              onChanged: (i) => _set(() {
                _splitShares = i == 1;
                _reduce = i == 2;
              }),
            ),
          ),
      ],
      TileRow([
        _accountTile(_trade == EntryType.buy ? '扣款帳戶' : '入帳帳戶'),
        _dateTile(),
      ]),
      if (_trading && sell && !_viewing)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Segments(
            labels: const ['先進先出', '平均成本'],
            selected: _average ? 1 : 0,
            onChanged: (i) => _set(() => _average = i == 1),
          ),
        ),
      if (_trading && _amount > 0)
        TileRow([
          _chargeTile('手續費', fee, suggested.$1, (v) => _tradeFee = v),
          if (sell) _chargeTile('證交稅', tax, suggested.$2, (v) => _tradeTax = v),
        ]),
      if (_trading && _amount > 0)
        FormBlock(
          child: Column(
            children: [
              _Line(
                sell ? '實收' : '應付',
                groupDigits(sell ? _amount - fee - tax : _amount + fee),
                strong: true,
              ),
              if (cost != null)
                _Line(
                  '已實現損益',
                  signed(_amount - fee - tax - cost),
                  color: _amount - fee - tax < cost
                      ? Hue.negative
                      : Hue.positive,
                ),
              _Line('交割日', '${settled.month}/${settled.day}'),
            ],
          ),
        ),
      _noteField(),
    ];
  }

  /// A trade's fee or tax: what the broker charged, typed in, or the
  /// suggestion until then.
  Widget _chargeTile(
    String label,
    int value,
    int suggested,
    void Function(int value) keep,
  ) {
    return Tile(
      icon: Glyph.coins,
      label: label,
      value: groupDigits(value),
      valueColor: value > 0 ? Hue.negative : Hue.ink,
      size: 15,
      sub: value == suggested ? '依費率試算，點此修改' : '試算 ${groupDigits(suggested)}',
      onTap: () async {
        final typed = await _ask(label, value);
        if (typed != null) _set(() => keep(typed));
      },
    );
  }
}
