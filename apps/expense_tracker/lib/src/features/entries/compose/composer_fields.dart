part of 'composer.dart';

/// The form's fields, one builder each, by kind of entry. Each kind's
/// list starts at the amount (a trade's at what is traded).
extension _Fields on _ComposerState {
  /// Two cards side by side, such as the account and the day.
  Widget _pair(Widget left, Widget right) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Row(
      children: [
        Expanded(child: left),
        const SizedBox(width: 8),
        Expanded(child: right),
      ],
    ),
  );

  Widget _accountPick(String label) {
    final account = _ledger.account(_f.account);
    return _Pick(
      icon: accountIcon(account),
      label: label,
      value: account.name,
      onTap: () async {
        final picked = await _pickAccount(label, _f.account);
        if (picked == null) return;
        _set(() {
          _f.account = picked;
          _f.home = null;
        });
      },
    );
  }

  Widget _datePick() {
    final day = '${_f.date.month}/${_f.date.day}';
    return _Pick(
      icon: Glyph.calendar,
      label: '日期',
      value: _f.date == _ledger.today
          ? '今天 $day'
          : '$day 週${weekdayNames[_f.date.weekday - 1]}',
      onTap: _pickDate,
    );
  }

  /// The worth in NT$ of a foreign amount, at today's rate until typed.
  Widget _homeTile() {
    final value = _f.homeValue;
    final rate = _ledger.rates[_f.currency];
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Tile(
        icon: Glyph.coins,
        label: '折合台幣',
        value: value == null ? '請輸入' : groupDigits(value),
        valueColor: value == null ? Hue.hint : Hue.ink,
        size: 15,
        sub: _f.home != null || rate == null ? null : '臺銀即期買入 $rate',
        onTap: () async {
          final typed = await _ask('折合台幣', value ?? 0);
          if (typed != null) _set(() => _f.home = typed);
        },
      ),
    );
  }

  Widget _noteField({int lines = 1, String hint = '寫點備註…'}) {
    if (_viewing && _note.text.isEmpty) return const SizedBox.shrink();
    // Looked at, the note is words on the page, once; a box to type in
    // only while editing.
    if (_viewing) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: GlyphIcon(Glyph.note, size: 18, color: Hue.muted),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(_note.text, style: const TextStyle(fontSize: 15)),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: TextField(
        controller: _note,
        minLines: lines,
        maxLines: math.max(lines, 3),
        decoration: InputDecoration(
          hintText: hint,
          filled: true,
          fillColor: Hue.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  /// The note, folded to one line until opened or written in.
  Widget _noteRow() {
    if (_viewing && _note.text.isEmpty) return const SizedBox.shrink();
    if (_f.more || _note.text.isNotEmpty || _viewing) return _noteField();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _set(() => _f.more = true),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              GlyphIcon(Glyph.note, size: 18, color: Hue.muted),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  '備註',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Hue.muted,
                  ),
                ),
              ),
              RotatedBox(
                quarterTurns: 1,
                child: GlyphIcon(Glyph.next, size: 16, color: Hue.faint),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _fields() {
    if (_f.refunded != null) {
      return [_hero(), _pair(_accountPick('退回到'), _datePick()), _noteRow()];
    }
    switch (_f.mode) {
      case ComposeMode.expense || ComposeMode.income:
        final expense = _f.mode == ComposeMode.expense;
        final parts = _f.parts;
        return [
          _hero(
            under: _f.lending
                ? _lendRow()
                : parts == null
                ? _usual()
                : _splitState(),
          ),
          if (parts != null)
            _AllocationBar(
              parts: [
                for (final (name, value) in parts)
                  (_ledger.category(name), value),
              ],
              onTap: _editPart,
            ),
          _categories(expense),
          _pair(_accountPick(expense ? '付款帳戶' : '收款帳戶'), _datePick()),
          if (_f.foreign) _homeTile(),
          if (_f.onCard)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Tile(
                icon: Glyph.card,
                label: '分期付款',
                value: _f.installments < 2
                    ? '不分期'
                    : '${_f.installments} 期 · 每期 '
                          '${groupDigits(_f.amount ~/ _f.installments)}',
                size: 15,
                onTap: _pickInstallments,
              ),
            ),
          _extras(expense),
        ];
      case ComposeMode.transfer:
        return [
          _hero(under: _usualTransfers()),
          _ends(),
          if (_f.crossing) _receivedTile(),
          if (!_f.takesFee)
            Padding(padding: const EdgeInsets.only(top: 12), child: _datePick())
          else
            _pair(
              _f.takesFee
                  ? _Pick(
                      icon: Glyph.coins,
                      label: '手續費',
                      value: '手續費 ${groupDigits(_f.fee)}',
                      valueColor: _f.fee > 0 ? Hue.negative : Hue.ink,
                      onTap: () async {
                        final value = await _ask('手續費', _f.fee);
                        if (value != null) _set(() => _f.fee = value);
                      },
                    )
                  : const SizedBox.shrink(),
              _datePick(),
            ),
          _noteRow(),
        ];
      case ComposeMode.lend:
        return _lendFields();
      case ComposeMode.investment:
        return _investmentFields();
    }
  }

  /// The two accounts of a transfer side by side, each with what it will
  /// hold afterwards, and between them the arrow that turns them round.
  Widget _ends() {
    final from = _ledger.account(_f.account);
    final to = _ledger.account(_f.to);
    final fee = _f.takesFee ? _f.fee : 0;
    final arrives = _f.crossing ? _f.receivedValue ?? 0 : _f.amount;
    final moved = _f.amount > 0;
    String held(Account a, int change) {
      final now = _ledger.balance(a.id);
      return _ledger.moneyIn(now + change, a.currency);
    }

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Row(
            children: [
              Expanded(
                child: _TransferEnd(
                  account: from,
                  label: '轉出帳戶',
                  after: moved
                      ? '剩 ${held(from, -_f.amount - fee)}'
                      : '餘額 ${held(from, 0)}',
                  onTap: () async {
                    final picked = await _pickAccount('轉出帳戶', _f.account);
                    if (picked == null) return;
                    _set(() {
                      _f.account = picked;
                      _f.received = null;
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _TransferEnd(
                  account: to,
                  label: '轉入帳戶',
                  end: true,
                  after: moved ? '變 ${held(to, arrives)}' : '餘額 ${held(to, 0)}',
                  onTap: () async {
                    final picked = await _pickAccount('轉入帳戶', _f.to);
                    if (picked == null) return;
                    _set(() {
                      _f.to = picked;
                      _f.received = null;
                    });
                  },
                ),
              ),
            ],
          ),
          IconButton(
            tooltip: '對調',
            onPressed: () => _set(_f.swapEnds),
            style: IconButton.styleFrom(
              backgroundColor: Hue.white,
              elevation: 2,
              shadowColor: const Color(0x33000000),
            ),
            icon: const GlyphIcon(Glyph.arrow, size: 18, color: Hue.transfer),
          ),
        ],
      ),
    );
  }

  /// What a transfer between currencies delivers, at today's rates until
  /// typed.
  Widget _receivedTile() {
    final value = _f.receivedValue;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Tile(
        icon: Glyph.coins,
        label: '轉入金額',
        value: value == null ? '請輸入' : amountIn(value, _f.toCurrency),
        valueColor: value == null ? Hue.hint : Hue.ink,
        size: 15,
        sub: _f.received == null && value != null ? '依臺銀即期匯率換算' : null,
        onTap: () async {
          final typed = await _ask('轉入金額', value ?? 0, unit: _f.toCurrency);
          if (typed != null) _set(() => _f.received = typed);
        },
      ),
    );
  }

  /// 常用: spending or income recorded alike again and again, each a tap
  /// away from a filled form, and, for spending, 掃發票 to fill it from a
  /// paper e-invoice; first of all 代墊 or 對方還錢, a switch to money paid
  /// for someone or paid back. On a new entry, 常用 stays once an amount
  /// is typed, so the form keeps its shape, and a tap still fills it all.
  Widget? _usual() {
    final income = _f.mode == ComposeMode.income;
    if (_f.mode != ComposeMode.expense && !income) return null;
    final fresh = !_viewing && widget.entry == null && widget.draft == null;
    final lend = !_viewing && !_f.foreign
        ? _UsualChip(
            icon: Glyph.heart,
            name: income ? '對方還錢' : '代墊',
            strong: true,
            onTap: income ? () => _lend(back: true) : _pickLent,
          )
        : null;
    final usual = fresh ? _ledger.usual(income: income) : const <Entry>[];
    final scan = fresh && widget.scan != null && !income;
    if (usual.isEmpty && !scan && lend == null) return null;
    return _UsualRow(lead: lend, [
      if (scan) _UsualChip(icon: Glyph.scan, name: '掃發票', onTap: _scanInvoice),
      for (final (e, category) in [
        for (final e in usual) (e, _ledger.category(e.category)),
      ])
        _UsualChip(
          icon: iconFor(category.icon),
          name: e.merchant.isEmpty ? e.category : e.merchant,
          amount: groupDigits(e.amount),
          onTap: () => _set(() => _f.startFrom(e)),
        ),
    ]);
  }

  /// 常用轉帳: the same two accounts and amount moved again and again, a
  /// tap away; on a new transfer only, and kept once an amount is typed.
  Widget? _usualTransfers() {
    if (_viewing || widget.entry != null || widget.draft != null) {
      return null;
    }
    final usual = _ledger.usualTransfers();
    if (usual.isEmpty) return null;
    return _UsualRow([
      for (final e in usual)
        _UsualChip(
          icon: Glyph.transfer,
          name:
              '${_ledger.account(e.account).name}→'
              '${_ledger.account(e.to ?? e.account).name}',
          amount: groupDigits(e.amount),
          onTap: () => _set(() => _f.startTransferFrom(e)),
        ),
    ]);
  }

  /// Under the amount of a split: whether the parts add up, and 平均分配.
  Widget _splitState() {
    final parts = _f.parts ?? const [];
    final used = parts.fold(0, (sum, p) => sum + p.$2);
    final left = _f.amount - used;
    return _Bubbles([
      _Bubble(
        left == 0
            ? '✓ 剛好分完'
            : left > 0
            ? '還剩 ${groupDigits(left)}'
            : '多了 ${groupDigits(-left)}',
        null,
        color: left == 0 ? Hue.positive.withValues(alpha: 0.14) : null,
        ink: left == 0 ? Hue.positive : Hue.negative,
      ),
      if (!_viewing && parts.isNotEmpty) _Bubble('平均分配', _evenly),
    ]);
  }

  /// The categories as a row of marks that slides sideways, then 全部
  /// and 新增; 拆分 kept still at the right end. Grey until picked, then in
  /// the tab's colour; while splitting, each part in its category's own
  /// colour, and a tap adds a category as a part or takes it away.
  Widget _categories(bool expense) {
    final parts = _f.parts;
    final splitting = parts != null;
    final inParts = {for (final p in parts ?? const <(String, int)>[]) p.$1};
    final choices = _f.categoryChoices();
    // Four of the most used, then 全部 and 新增: as many as the row shows
    // without sliding.
    final shown = choices.take(4).toList();
    final lending = _f.mode == ComposeMode.lend;
    if (!splitting &&
        _f.category.isNotEmpty &&
        !shown.contains(_f.category) &&
        shown.isNotEmpty) {
      shown[shown.length - 1] = _f.category;
    }
    for (final name in inParts) {
      if (!shown.contains(name)) shown.add(name);
    }
    final items = [
      for (final category in [for (final n in shown) _ledger.category(n)])
        _StripItem(
          label: category.name,
          icon: iconFor(category.icon),
          color: splitting ? category.color : _color,
          picked: splitting
              ? inParts.contains(category.name)
              : !lending && category.name == _f.category,
          onTap: splitting
              ? () => _set(() => _f.togglePart(category.name))
              : () => _pickCategoryName(category.name),
        ),
      if (choices.length > shown.length || splitting)
        _StripItem(
          label: '全部',
          icon: Glyph.categories,
          color: _color,
          picked: false,
          onTap: splitting
              ? _addPart
              : () async {
                  final picked = await _pickCategory(_f.category);
                  if (picked != null) _pickCategoryName(picked);
                },
        ),
      if (!_viewing && !splitting)
        _StripItem(
          label: '新增',
          icon: Glyph.add,
          color: _color,
          picked: false,
          onTap: () async {
            final made = await _newCategory();
            if (made != null) _pickCategoryName(made);
          },
        ),
    ];
    final canSplit =
        expense && !_viewing && !_f.foreign && !lending && !_f.lending;
    return _Strip(
      items: items,
      pinned: canSplit
          ? _StripItem(
              label: splitting ? '拆分中' : '拆分',
              icon: Glyph.sliders,
              color: Hue.negative,
              solid: splitting,
              picked: false,
              onTap: _split,
            )
          : null,
    );
  }

  /// The merchant, tags, note and receipt under one heading at the foot
  /// of the form, opened and closed with it; closed, the heading shows
  /// what is filled in. Open, they are no list: the note a large box with
  /// the receipt beside it, merchants and tags words to tap in a row.
  Widget _extras(bool expense) {
    final filled = [
      if (expense && _f.merchant.isNotEmpty) _f.merchant,
      for (final tag in _f.tags) '#$tag',
      if (_note.text.trim().isNotEmpty) _note.text.trim(),
      if (_f.receipt != null) '收據',
    ];
    final photos = widget.photos;
    final withPhoto = photos != null || _f.receipt != null;
    if (_viewing && filled.isEmpty) return const SizedBox.shrink();
    final open = _f.more || _viewing;
    final names = [if (expense) '商家', '標籤', '備註', if (withPhoto) '收據'];
    return _fold(
      closed: filled.isEmpty ? names.join('、') : filled.join(' · '),
      open: open,
      body: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _noteField(lines: 3)),
            if (photos != null && (!_viewing || _f.receipt != null)) ...[
              const SizedBox(width: 8),
              _receiptSquare(photos),
            ],
          ],
        ),
        if (expense && (!_viewing || _f.merchant.isNotEmpty)) ...[
          const _GroupLabel('商家'),
          _WordRow([
            for (final name in _merchantChoices())
              _WordChip(
                name,
                () => _set(() {
                  if (name == _f.merchant) {
                    _f.merchant = '';
                  } else {
                    _f.pickMerchant(name);
                  }
                }),
                color: _color,
                picked: name == _f.merchant,
              ),
            if (!_viewing) _WordChip('＋', _pickMerchant, color: _color),
          ]),
        ],
        if (!_viewing || _f.tags.isNotEmpty) ...[
          const _GroupLabel('標籤'),
          _WordRow([
            for (final tag in _tagChoices())
              _WordChip(
                '#$tag',
                () => _set(() {
                  _f.tags = _f.tags.contains(tag)
                      ? [
                          for (final t in _f.tags)
                            if (t != tag) t,
                        ]
                      : [..._f.tags, tag];
                }),
                color: _color,
                picked: _f.tags.contains(tag),
              ),
            if (!_viewing) _WordChip('＋', _pickTags, color: _color),
          ]),
        ],
      ],
    );
  }

  /// The merchants to tap: the one chosen first, then the most used.
  List<String> _merchantChoices() {
    final known = _ledger.merchants.take(8).toList();
    final chosen = _f.merchant;
    return [
      if (chosen.isNotEmpty) chosen,
      for (final name in known)
        if (name != chosen) name,
    ];
  }

  /// The tags to tap: those on the entry first, then the others in use.
  List<String> _tagChoices() => [
    ..._f.tags,
    for (final tag in _ledger.tags.take(8))
      if (!_f.tags.contains(tag)) tag,
  ];

  /// A heading at the foot of the form that opens and closes [body]:
  /// closed, [closed] says what is in it.
  Widget _fold({
    required String closed,
    required bool open,
    required List<Widget> body,
  }) {
    // Looked at, there is nothing to open or close: what is filled in
    // shows, with no heading repeating it.
    if (_viewing) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: body,
        ),
      );
    }
    final heading = InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: _viewing ? null : () => _set(() => _f.more = !_f.more),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
        child: Row(
          children: [
            const GlyphIcon(Glyph.note, size: 18, color: Hue.muted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                closed,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: open ? FontWeight.w700 : FontWeight.w600,
                  color: open ? Hue.ink : Hue.muted,
                ),
              ),
            ),
            if (!_viewing)
              RotatedBox(
                quarterTurns: open ? 3 : 1,
                child: const GlyphIcon(Glyph.next, size: 16, color: Hue.faint),
              ),
          ],
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 4),
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
                    children: body,
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  /// The receipt photo as a square beside the note: its thumbnail, which
  /// opens it whole, or a camera mark that asks for one.
  Widget _receiptSquare(ReceiptPhotos photos) {
    final receipt = _f.receipt;
    Future<void> take({required bool camera}) async {
      try {
        final name = await photos.take(camera: camera);
        if (name != null) _set(() => _f.receipt = name);
      } on Object {
        _set(() => _problem = camera ? '無法開啟相機' : '無法讀取這張照片');
      }
    }

    const size = 84.0;
    if (receipt == null) {
      return TapArea(
        label: '收據',
        onTap: () async {
          final camera = await _open<bool>(
            '收據',
            (done) => Row(
              children: [
                Expanded(
                  child: _WordChip('拍照', () => done(true), color: _color),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _WordChip('從相簿', () => done(false), color: _color),
                ),
              ],
            ),
          );
          if (camera != null) await take(camera: camera);
        },
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Hue.line, width: 1.5),
          ),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GlyphIcon(Glyph.camera, size: 22, color: Hue.muted),
              SizedBox(height: 4),
              Text(
                '收據',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: Hue.muted,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Stack(
      clipBehavior: Clip.none,
      children: [
        TapArea(
          label: '查看收據',
          onTap: () => unawaited(_showReceipt(photos.image(receipt))),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image(
              image: photos.image(receipt),
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const SizedBox(
                width: size,
                height: size,
                child: Center(child: GlyphIcon(Glyph.image, color: Hue.faint)),
              ),
            ),
          ),
        ),
        if (!_viewing)
          Positioned(
            right: -10,
            top: -10,
            child: IconButton(
              tooltip: '移除收據',
              onPressed: () => _set(() => _f.receipt = null),
              style: IconButton.styleFrom(backgroundColor: Hue.white),
              icon: const GlyphIcon(Glyph.close, size: 14, color: Hue.muted),
            ),
          ),
      ],
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
}
