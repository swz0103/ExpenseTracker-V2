part of 'composer.dart';

/// The investment fields: a buy or sale from shares and price with the
/// broker's fee and tax, or a dividend with its premium and any change in
/// the shares held.
extension _InvestmentFields on _ComposerState {
  List<Widget> _investmentFields() {
    final sell = _f.trade == EntryType.sell;
    const trades = [EntryType.buy, EntryType.sell, EntryType.dividend];
    // In the order a trade is written down: buy, sell or dividend; what it
    // comes to, large, where the other tabs have their amount; what, how
    // many at what price; when and from where; then the rest folded away.
    return [
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Segments(
          labels: const ['買進', '賣出', '股息'],
          selected: trades.indexOf(_f.trade),
          selectedColor: _color,
          onChanged: (i) => _changeTrade(trades[i]),
        ),
      ),
      if (_f.trading)
        _AmountHero(
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
    final code = _f.holding;
    final held = code == null ? null : _ledger.holding(code);
    final (fee, tax) = _f.charges;
    final suggested = _f.suggested;
    final sell = _f.trade == EntryType.sell;
    final settles = _f.settlement;
    final cost =
        sell && code != null && held != null && _f.shares <= held.shares
        ? _ledger.saleCost(code, _f.shares, average: _f.average)
        : null;
    final settled = settlementDay(_f.date);
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
        Row(
          children: [
            Expanded(
              child: _EqBox(
                '成交',
                groupDigits(_f.amount),
                _viewing ? null : _calculate,
              ),
            ),
            _operator(sell ? '−' : '＋'),
            Expanded(
              child: _charge('手續費', fee, suggested.$1, (v) => _f.tradeFee = v),
            ),
            if (sell) ...[
              _operator('−'),
              Expanded(
                child: _charge('證交稅', tax, suggested.$2, (v) {
                  _f.tradeTax = v;
                }),
              ),
            ],
          ],
        ),
        if (sell && !_viewing)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              children: [
                const Padding(
                  padding: EdgeInsets.only(left: 4, right: 10),
                  child: Text(
                    '成本算法',
                    style: TextStyle(
                      fontSize: 12.5,
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
            padding: const EdgeInsets.only(top: 8),
            child: _OutcomeCard(
              title: cost == null ? '交割' : '已實現損益',
              sub: cost == null
                  ? '${settled.month}/${settled.day}'
                  : '成本 ${groupDigits(cost)} · 交割 ${settled.month}/${settled.day}',
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
    final change = !_f.shareChange
        ? 0
        : _f.reduce
        ? 3
        : _f.splitShares
        ? 2
        : 1;
    final filled = [
      if (_f.shareChange)
        '${const ['', '配股', '分割', '減資'][change]} ${groupDigits(_f.shares)} 股',
      if (_f.withheld > 0) '二代健保 ${groupDigits(_f.withheld)}',
      if (_note.text.trim().isNotEmpty) _note.text.trim(),
    ];
    return _fold(
      closed: filled.isEmpty ? '配股、二代健保、備註' : filled.join(' · '),
      open: _f.more || _viewing,
      body: [
        if (!_viewing || _f.shareChange) ...[
          const _GroupLabel('股數有變動'),
          Segments(
            labels: const ['沒有', '配股', '分割', '減資'],
            selected: change,
            selectedColor: _color,
            onChanged: (i) => _set(() {
              _f.shareChange = i > 0;
              _f.splitShares = i == 2;
              _f.reduce = i == 3;
              if (i == 0) _f.shares = 0;
            }),
          ),
        ],
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            children: [
              if (_f.shareChange) ...[
                Expanded(
                  child: _EqBox(
                    _f.reduce
                        ? '減資減少'
                        : _f.splitShares
                        ? '分割增加'
                        : '配股增加',
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
                const SizedBox(width: 8),
              ],
              if (!_f.reducing)
                Expanded(
                  child: _EqBox(
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
            padding: EdgeInsets.fromLTRB(4, 6, 4, 0),
            child: Text('單筆股息 2 萬以上才扣二代健保，會自動算', style: mutedSmall),
          ),
        _noteField(lines: 2),
      ],
    );
  }

  Widget _operator(String sign) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 5),
    child: Text(
      sign,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: Hue.faint,
      ),
    ),
  );

  /// The holdings as one row of pills, those held first; the square at
  /// the right end, kept still, opens them all and 新增.
  Widget _codes() {
    final code = _f.holding;
    final holdings = _ledger.holdings;
    final known = {for (final h in holdings) h.code};
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  if (code != null && !known.contains(code))
                    _CodePill(code: code, name: '', picked: true, onTap: () {}),
                  for (final h in holdings) ...[
                    const SizedBox(width: 6),
                    _CodePill(
                      code: h.code,
                      name: _shortName(h.name),
                      picked: h.code == code,
                      onTap: () => _set(() => _f.holding = h.code),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Container(
            width: 1,
            height: 24,
            margin: const EdgeInsets.only(left: 4),
            color: Hue.line,
          ),
          _SquareButton(
            icon: Glyph.categories,
            label: '全部標的',
            onTap: _pickHolding,
          ),
        ],
      ),
    );
  }

  /// A trade's fee or tax in its sum: what the broker charged, typed in,
  /// or the suggestion until then (試算).
  Widget _charge(
    String label,
    int value,
    int suggested,
    void Function(int value) keep,
  ) {
    return _EqBox(
      value == suggested ? '$label（試算）' : label,
      groupDigits(value),
      _viewing
          ? null
          : () async {
              final typed = await _ask(label, value);
              if (typed != null) _set(() => keep(typed));
            },
    );
  }
}

/// Every holding on a page of its own: a search, then cards three to a
/// row with their code, short name and shares, and 新增 at the end.
class _HoldingChoices extends StatefulWidget {
  const _HoldingChoices({
    required this.ledger,
    required this.selected,
    required this.onPick,
    this.onAdd,
  });

  final Ledger ledger;
  final String? selected;
  final ValueChanged<String> onPick;
  final VoidCallback? onAdd;

  @override
  State<_HoldingChoices> createState() => _HoldingChoicesState();
}

class _HoldingChoicesState extends State<_HoldingChoices> {
  var _typed = '';

  @override
  Widget build(BuildContext context) {
    final ledger = widget.ledger;
    final words = _typed.trim().toLowerCase();
    final cards = <Widget>[
      for (final h in ledger.holdings)
        if (words.isEmpty ||
            h.code.toLowerCase().contains(words) ||
            h.name.toLowerCase().contains(words))
          _HoldingCard(
            code: h.code,
            name: _shortName(holdingLabel(h)),
            held: h.shares > 0
                ? '${ledger.orDots(groupDigits(h.shares))} 股'
                : '已賣完',
            picked: h.code == widget.selected,
            onTap: () => widget.onPick(h.code),
          ),
    ];
    final add = widget.onAdd;
    if (add != null) {
      cards.add(
        Material(
          color: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Hue.line, width: 1.5),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: add,
            child: const SizedBox(
              height: 74,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GlyphIcon(Glyph.add, size: 20, color: Hue.muted),
                  Text(
                    '新增',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: Hue.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          onChanged: (text) => setState(() => _typed = text),
          decoration: InputDecoration(
            hintText: '搜尋代號或名稱',
            isDense: true,
            filled: true,
            fillColor: Hue.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 10),
        for (var i = 0; i < cards.length; i += 3)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var j = i; j < i + 3; j++) ...[
                  if (j > i) const SizedBox(width: 8),
                  Expanded(
                    child: j < cards.length ? cards[j] : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

/// What a trade comes to beyond its sums, on a white card: its name and
/// what it rests on on the left, the figure on the right in [color].
class _OutcomeCard extends StatelessWidget {
  const _OutcomeCard({
    required this.title,
    required this.sub,
    required this.color,
    this.value,
  });

  final String title;
  final String sub;
  final String? value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final figure = value;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Hue.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: Hue.tileShadow,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(sub, style: const TextStyle(fontSize: 12, color: Hue.muted)),
              ],
            ),
          ),
          if (figure != null)
            Text(
              figure,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
        ],
      ),
    );
  }
}
