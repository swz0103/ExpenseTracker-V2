part of 'composer.dart';

/// The form's fields, one builder each, by kind of entry.
extension _Fields on _ComposerState {
  Widget _accountTile(String label) {
    final account = _ledger.account(_account);
    return Tile(
      icon: accountIcon(account),
      label: label,
      value: account.name,
      size: 15,
      onTap: () async {
        final picked = await _pickAccount('選擇帳戶', _account);
        if (picked == null) return;
        _set(() {
          _account = picked;
          _home = null;
        });
      },
    );
  }

  /// The worth in NT$ of a foreign amount, at today's rate until typed.
  Widget _homeTile() {
    final value = _homeValue;
    final rate = _ledger.rates[_currency];
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Tile(
        icon: Glyph.coins,
        label: '折合台幣',
        value: value == null ? '請輸入' : groupDigits(value),
        valueColor: value == null ? Hue.hint : Hue.ink,
        size: 15,
        sub: _home != null || rate == null ? null : '臺銀即期買入 $rate',
        onTap: () async {
          final typed = await _ask('折合台幣', value ?? 0);
          if (typed != null) _set(() => _home = typed);
        },
      ),
    );
  }

  Widget _dateTile() {
    final day = '${_date.month}/${_date.day}';
    return Tile(
      icon: Glyph.calendar,
      label: '日期',
      value: _date == _ledger.today
          ? '今天 $day'
          : '$day 週${weekdayNames[_date.weekday - 1]}',
      size: 15,
      onTap: _pickDate,
    );
  }

  Widget _noteField() {
    if (_viewing && _note.text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: TextField(
        controller: _note,
        minLines: 1,
        maxLines: 3,
        decoration: InputDecoration(
          hintText: '備註（選填）',
          prefixIcon: const Padding(
            padding: EdgeInsets.all(12),
            child: GlyphIcon(Glyph.note, size: 18, color: Hue.accent),
          ),
          filled: true,
          fillColor: Hue.tile,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  List<Widget> _fields() {
    if (_refunded != null) {
      return [
        TileRow([_accountTile('退回到'), _dateTile()]),
        _noteField(),
      ];
    }
    switch (_mode) {
      case ComposeMode.expense || ComposeMode.income:
        final expense = _mode == ComposeMode.expense;
        return [
          _categories(expense),
          TileRow([_accountTile(expense ? '付款帳戶' : '收款帳戶'), _dateTile()]),
          if (_foreign) _homeTile(),
          if (_onCard)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Tile(
                icon: Glyph.card,
                label: '分期付款',
                value: _installments < 2
                    ? '不分期'
                    : '$_installments 期 · 每期 '
                          '${groupDigits(_amount ~/ _installments)}',
                size: 15,
                onTap: _pickInstallments,
              ),
            ),
          _extras(expense),
        ];
      case ComposeMode.transfer:
        final from = _ledger.account(_account);
        final to = _ledger.account(_to);
        return [
          _Block(
            child: Row(
              children: [
                Expanded(
                  child: _AccountEnd(
                    label: '從',
                    account: from,
                    balance: _ledger.balance(from.id),
                    onTap: () async {
                      final picked = await _pickAccount('轉出帳戶', _account);
                      if (picked == null) return;
                      _set(() {
                        _account = picked;
                        _received = null;
                      });
                    },
                  ),
                ),
                const GlyphIcon(Glyph.arrow, size: 22, color: Hue.accent),
                Expanded(
                  child: _AccountEnd(
                    label: '到',
                    account: to,
                    balance: _ledger.balance(to.id),
                    end: true,
                    onTap: () async {
                      final picked = await _pickAccount('轉入帳戶', _to);
                      if (picked == null) return;
                      _set(() {
                        _to = picked;
                        _received = null;
                      });
                    },
                  ),
                ),
              ],
            ),
          ),
          if (_crossing) _receivedTile(),
          TileRow([
            if (_takesFee)
              Tile(
                icon: Glyph.coins,
                label: '手續費',
                value: groupDigits(_fee),
                valueColor: _fee > 0 ? Hue.negative : Hue.ink,
                size: 15,
                onTap: () async {
                  final value = await _ask('手續費', _fee);
                  if (value != null) _set(() => _fee = value);
                },
              ),
            _dateTile(),
          ]),
          _noteField(),
        ];
      case ComposeMode.lend:
        return _lendFields();
      case ComposeMode.investment:
        return _investmentFields();
    }
  }

  /// 代墊 under 支出 (paid for someone) or 對方還錢 under 收入. Each
  /// person has an account of their own that keeps what they owe.
  List<Widget> _lendFields() {
    final person = _to.isEmpty ? null : _ledger.account(_to);
    final owed = person == null ? 0 : _ledger.balance(person.id);
    return [
      _categories(!_back),
      TileRow([
        Tile(
          icon: Glyph.heart,
          label: _back ? '誰還錢' : '幫誰付',
          value: person?.name ?? '新增對象',
          valueColor: person == null ? Hue.accent : Hue.ink,
          sub: person == null || owed == 0 ? null : '目前欠 ${groupDigits(owed)}',
          size: 15,
          onTap: _pickPerson,
        ),
      ]),
      TileRow([_accountTile(_back ? '收款帳戶' : '付款帳戶'), _dateTile()]),
      _extras(false),
    ];
  }

  /// Picks whom the money is for, or adds a new person.
  Future<void> _pickPerson() async {
    const adding = '';
    final picked = _people.isEmpty
        ? adding
        : await pickOption<String>(
            context,
            title: '代墊對象',
            selected: _to,
            columns: 3,
            options: [
              for (final a in _people)
                Option(a.id, a.name, accountIcon(a), accountColor(a.kind)),
              const Option(adding, '新增對象', Glyph.add, Hue.accent),
            ],
          );
    if (picked == null || !mounted) return;
    if (picked != adding) {
      _set(() => _to = picked);
      return;
    }
    final name = await askText(context, '代墊對象的名字');
    if (name == null || name.trim().isEmpty || !mounted) return;
    final account = Account(
      _ledger.newId(),
      name.trim(),
      AccountKind.receivable,
      0,
    );
    _ledger.addAccount(account);
    _set(() => _to = account.id);
  }

  /// What a transfer between currencies delivers, at today's rates until
  /// typed.
  Widget _receivedTile() {
    final value = _receivedValue;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Tile(
        icon: Glyph.coins,
        label: '轉入金額',
        value: value == null ? '請輸入' : amountIn(value, _toCurrency),
        valueColor: value == null ? Hue.hint : Hue.ink,
        size: 15,
        sub: _received == null && value != null ? '依臺銀即期匯率換算' : null,
        onTap: () async {
          final typed = await _ask('轉入金額', value ?? 0, unit: _toCurrency);
          if (typed != null) _set(() => _received = typed);
        },
      ),
    );
  }

  /// The categories as a grid of marks, or the parts of a split.
  Widget _categories(bool expense) {
    final parts = _parts;
    final used = parts == null ? 0 : parts.fold(0, (sum, p) => sum + p.$2);
    final left = _amount - used;
    final choices = _categoryChoices();
    // Five, then 更多, 代墊 and 新增 fill two rows of four.
    final shown = choices.take(5).toList();
    final lending = _mode == ComposeMode.lend;
    if (shown.isNotEmpty &&
        !shown.contains(_category) &&
        _category.isNotEmpty) {
      shown[shown.length - 1] = _category;
    }
    return _Block(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const IconChip(Glyph.categories),
              const SizedBox(width: 8),
              Text(
                parts == null ? '分類' : '分類 · 拆成 ${parts.length} 筆',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: Hue.accent,
                ),
              ),
              const Spacer(),
              if (parts != null && !_viewing) ...[
                _Chip('均分', _evenly),
                const SizedBox(width: 6),
              ],
              if (expense && !_viewing && !_foreign && !lending)
                _Chip(parts == null ? '拆分' : '不拆分', _split),
            ],
          ),
          const SizedBox(height: 8),
          if (parts == null)
            Wrap(
              runSpacing: 8,
              children: [
                for (final name in shown)
                  _CategoryChoice(
                    category: _ledger.category(name),
                    picked: !lending && name == _category,
                    onTap: () => _pickCategoryName(name),
                  ),
                if (choices.length > shown.length)
                  _CategoryChoice(
                    category: const Category('更多', 'other', Hue.muted),
                    picked: false,
                    onTap: () async {
                      final picked = await _pickCategory(_category);
                      if (picked != null) _pickCategoryName(picked);
                    },
                  ),
                if ((!_viewing && !_foreign) || lending)
                  _CategoryChoice(
                    category: Category(
                      expense ? '代墊' : '對方還錢',
                      'heart',
                      Hue.receivable,
                    ),
                    picked: lending,
                    onTap: () => _lend(back: !expense),
                  ),
                if (!_viewing)
                  _CategoryChoice(
                    category: const Category('新增', 'add', Hue.accent),
                    picked: false,
                    onTap: _newCategory,
                  ),
              ],
            )
          else ...[
            for (final (i, (name, value)) in parts.indexed)
              _PartRow(
                category: _ledger.category(name),
                amount: value,
                share: _amount == 0 ? 0 : value / _amount,
                onTap: () => _editPart(i),
              ),
            if (!_viewing)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    _Link('＋ 再拆一個分類', _addPart),
                    const Spacer(),
                    Text(
                      '剩餘 ${groupDigits(left)}',
                      style: const TextStyle(fontSize: 12, color: Hue.muted),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
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

  /// Opens the fields a quick entry leaves out.
  /// The merchant, tags and note under one heading at the foot of the
  /// form, opened and closed with it; closed, the heading shows what is
  /// filled in.
  Widget _extras(bool expense) {
    final filled = [
      if (expense && _merchant.isNotEmpty) _merchant,
      for (final tag in _tags) '#$tag',
      if (_note.text.trim().isNotEmpty) _note.text.trim(),
      if (_receipt != null) '收據',
    ];
    final photos = receiptPhotos;
    final withPhoto = photos != null || _receipt != null;
    if (_viewing && filled.isEmpty) return const SizedBox.shrink();
    final open = _more || _viewing;
    final heading = InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: _viewing ? null : () => _set(() => _more = !_more),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
        child: Row(
          children: [
            const GlyphIcon(Glyph.note, size: 18, color: Hue.accent),
            const SizedBox(width: 8),
            Text(
              [if (expense) '商家', '標籤', '備註', if (withPhoto) '收據'].join('、'),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Hue.accent,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                open ? '' : filled.join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: const TextStyle(fontSize: 13, color: Hue.muted),
              ),
            ),
            if (!_viewing)
              RotatedBox(
                quarterTurns: open ? 3 : 1,
                child: const GlyphIcon(Glyph.next, size: 16, color: Hue.accent),
              ),
          ],
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          heading,
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: open
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (expense && (!_viewing || _merchant.isNotEmpty))
                        Tile(
                          icon: Glyph.store,
                          label: '商家',
                          value: _merchant.isEmpty ? '未填' : _merchant,
                          valueColor: _merchant.isEmpty ? Hue.hint : Hue.ink,
                          size: 15,
                          onTap: _pickMerchant,
                        ),
                      _tagBlock(),
                      _noteField(),
                      if (photos != null) _receiptBlock(photos),
                    ],
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  /// The receipt photo: a thumbnail that opens it whole, or buttons to
  /// take one or pick one from the gallery.
  Widget _receiptBlock(ReceiptPhotos photos) {
    final receipt = _receipt;
    if (_viewing && receipt == null) return const SizedBox.shrink();
    Future<void> take({required bool camera}) async {
      try {
        final name = await photos.take(camera: camera);
        if (name != null) _set(() => _receipt = name);
      } on Object {
        _set(() => _problem = camera ? '無法開啟相機' : '無法讀取這張照片');
      }
    }

    return _Block(
      child: Row(
        children: [
          const IconChip(Glyph.image),
          const SizedBox(width: 8),
          const Text(
            '收據',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: Hue.accent,
            ),
          ),
          const Spacer(),
          if (receipt == null) ...[
            _Chip('拍照', () => unawaited(take(camera: true))),
            const SizedBox(width: 6),
            _Chip('從相簿', () => unawaited(take(camera: false))),
          ] else ...[
            GestureDetector(
              onTap: () => unawaited(_showReceipt(photos.image(receipt))),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image(
                  image: photos.image(receipt),
                  width: 56,
                  height: 56,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox(
                    width: 56,
                    height: 56,
                    child: Center(
                      child: GlyphIcon(Glyph.image, color: Hue.faint),
                    ),
                  ),
                ),
              ),
            ),
            if (!_viewing) ...[
              const SizedBox(width: 8),
              _Chip('移除', () => _set(() => _receipt = null)),
            ],
          ],
        ],
      ),
    );
  }

  /// The whole receipt, to zoom into.
  Future<void> _showReceipt(ImageProvider image) => showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      insetPadding: const EdgeInsets.all(12),
      clipBehavior: Clip.antiAlias,
      child: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: InteractiveViewer(
          maxScale: 5,
          child: Image(image: image, fit: BoxFit.contain),
        ),
      ),
    ),
  );

  Widget _tagBlock() {
    if (_viewing && _tags.isEmpty) return const SizedBox.shrink();
    return _Block(
      child: Row(
        children: [
          const IconChip(Glyph.ticket),
          const SizedBox(width: 8),
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final tag in _tags) _TagChip('#$tag', solid: true),
                if (!_viewing)
                  GestureDetector(
                    onTap: _pickTags,
                    child: const _TagChip('＋ 標籤', solid: false),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

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
          sub: held == null ? null : '持有 ${groupDigits(held.shares)} 股',
          trailing: _viewing
              ? null
              : GestureDetector(
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
            child: _Link('＋ 配股、分割或減資', () => _set(() => _shareChange = true)),
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
        _Block(
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
}
