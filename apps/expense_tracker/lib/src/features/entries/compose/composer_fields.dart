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
      iconColor: accountColor(account.kind),
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
              GlyphIcon(Glyph.note, size: 18, color: Hue.accent),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  '備註',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Hue.accent,
                  ),
                ),
              ),
              RotatedBox(
                quarterTurns: 1,
                child: GlyphIcon(Glyph.next, size: 16, color: Hue.accent),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _fields() {
    if (_f.refunded != null) {
      return [
        _hero(),
        _pair(_accountPick('退回到'), _datePick()),
        _noteRow(),
      ];
    }
    switch (_f.mode) {
      case ComposeMode.expense || ComposeMode.income:
        final expense = _f.mode == ComposeMode.expense;
        final parts = _f.parts;
        return [
          _hero(under: parts == null ? _usual() : _splitState()),
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
              const SizedBox(width: 14),
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
  /// paper e-invoice. On a new entry only; it stays once an amount is
  /// typed, so the form keeps its shape, and a tap still fills it all.
  Widget? _usual() {
    final income = _f.mode == ComposeMode.income;
    if ((_f.mode != ComposeMode.expense && !income) ||
        _viewing ||
        widget.entry != null ||
        widget.draft != null) {
      return null;
    }
    final usual = _ledger.usual(income: income);
    final scan = widget.scan != null && !income;
    if (usual.isEmpty && !scan) return null;
    return _UsualRow([
      if (scan)
        _UsualChip(
          icon: Glyph.scan,
          color: Hue.accent,
          name: '掃發票',
          onTap: _scanInvoice,
        ),
      for (final (e, category) in [
        for (final e in usual) (e, _ledger.category(e.category)),
      ])
        _UsualChip(
          icon: iconFor(category.icon),
          color: category.color,
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
          color: Hue.transfer,
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

  /// The categories as a row of marks that slides sideways, then 代墊,
  /// 全部 and 新增; 拆分 kept still at the right end. While splitting, a
  /// tap adds a category as a part or takes it away.
  Widget _categories(bool expense) {
    final parts = _f.parts;
    final splitting = parts != null;
    final inParts = {for (final p in parts ?? const <(String, int)>[]) p.$1};
    final choices = _f.categoryChoices();
    // Four of the most used, then 代墊, 全部 and 新增: as many as the row
    // shows without sliding.
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
          color: category.color,
          picked: splitting
              ? inParts.contains(category.name)
              : !lending && category.name == _f.category,
          onTap: splitting
              ? () => _set(() => _f.togglePart(category.name))
              : () => _pickCategoryName(category.name),
        ),
      if (!splitting && ((!_viewing && !_f.foreign) || lending))
        _StripItem(
          label: expense ? '代墊' : '對方還錢',
          icon: Glyph.heart,
          color: Hue.receivable,
          picked: lending,
          onTap: () => _lend(back: !expense),
        ),
      if (choices.length > shown.length || splitting)
        _StripItem(
          label: '全部',
          icon: Glyph.categories,
          color: Hue.muted,
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
          color: Hue.accent,
          picked: false,
          onTap: _newCategory,
        ),
    ];
    final canSplit = expense && !_viewing && !_f.foreign && !lending;
    return _Strip(
      items: items,
      pinned: canSplit
          ? _StripItem(
              label: splitting ? '拆分中' : '拆分',
              icon: Glyph.sliders,
              color: splitting ? Hue.negative : Hue.accent,
              solid: splitting,
              picked: false,
              onTap: _split,
            )
          : null,
    );
  }

  /// Opens the fields a quick entry leaves out.
  /// The merchant, tags and note under one heading at the foot of the
  /// form, opened and closed with it; closed, the heading shows what is
  /// filled in.
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
    final heading = InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: _viewing ? null : () => _set(() => _f.more = !_f.more),
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
                style: mutedSmall,
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
                      if (expense && (!_viewing || _f.merchant.isNotEmpty))
                        Tile(
                          icon: Glyph.store,
                          label: '商家',
                          value: _f.merchant.isEmpty ? '未填' : _f.merchant,
                          valueColor: _f.merchant.isEmpty ? Hue.hint : Hue.ink,
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
    final receipt = _f.receipt;
    if (_viewing && receipt == null) return const SizedBox.shrink();
    Future<void> take({required bool camera}) async {
      try {
        final name = await photos.take(camera: camera);
        if (name != null) _set(() => _f.receipt = name);
      } on Object {
        _set(() => _problem = camera ? '無法開啟相機' : '無法讀取這張照片');
      }
    }

    return FormBlock(
      child: Row(
        children: [
          const IconChip(Glyph.image),
          const SizedBox(width: 8),
          const Text('收據', style: accentLabel),
          const Spacer(),
          if (receipt == null) ...[
            _Chip('拍照', () => unawaited(take(camera: true))),
            const SizedBox(width: 6),
            _Chip('從相簿', () => unawaited(take(camera: false))),
          ] else ...[
            TapArea(
              label: '查看收據',
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
              _Chip('移除', () => _set(() => _f.receipt = null)),
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
    if (_viewing && _f.tags.isEmpty) return const SizedBox.shrink();
    return FormBlock(
      child: Row(
        children: [
          const IconChip(Glyph.ticket),
          const SizedBox(width: 8),
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final tag in _f.tags) _TagChip('#$tag', solid: true),
                if (!_viewing)
                  TapArea(
                    label: '新增標籤',
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
}
