part of 'composer.dart';

/// The form's fields, one builder each, by kind of entry.
extension _Fields on _ComposerState {
  Widget _accountTile(String label) {
    final account = _ledger.account(_f.account);
    return Tile(
      icon: accountIcon(account),
      label: label,
      value: account.name,
      size: 15,
      onTap: () async {
        final picked = await _pickAccount('選擇帳戶', _f.account);
        if (picked == null) return;
        _set(() {
          _f.account = picked;
          _f.home = null;
        });
      },
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

  Widget _dateTile() {
    final day = '${_f.date.month}/${_f.date.day}';
    return Tile(
      icon: Glyph.calendar,
      label: '日期',
      value: _f.date == _ledger.today
          ? '今天 $day'
          : '$day 週${weekdayNames[_f.date.weekday - 1]}',
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
    if (_f.refunded != null) {
      return [
        TileRow([_accountTile('退回到'), _dateTile()]),
        _noteField(),
      ];
    }
    switch (_f.mode) {
      case ComposeMode.expense || ComposeMode.income:
        final expense = _f.mode == ComposeMode.expense;
        return [
          if (expense) _usual(),
          _categories(expense),
          TileRow([_accountTile(expense ? '付款帳戶' : '收款帳戶'), _dateTile()]),
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
        final from = _ledger.account(_f.account);
        final to = _ledger.account(_f.to);
        return [
          FormBlock(
            child: Row(
              children: [
                Expanded(
                  child: _AccountEnd(
                    label: '從',
                    account: from,
                    balance: _ledger.moneyIn(
                      _ledger.balance(from.id),
                      from.currency,
                    ),
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
                const GlyphIcon(Glyph.arrow, size: 22, color: Hue.accent),
                Expanded(
                  child: _AccountEnd(
                    label: '到',
                    account: to,
                    balance: _ledger.moneyIn(
                      _ledger.balance(to.id),
                      to.currency,
                    ),
                    end: true,
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
          ),
          if (_f.crossing) _receivedTile(),
          TileRow([
            if (_f.takesFee)
              Tile(
                icon: Glyph.coins,
                label: '手續費',
                value: groupDigits(_f.fee),
                valueColor: _f.fee > 0 ? Hue.negative : Hue.ink,
                size: 15,
                onTap: () async {
                  final value = await _ask('手續費', _f.fee);
                  if (value != null) _set(() => _f.fee = value);
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

  /// 常用: spending recorded alike again and again, each a tap away from
  /// a filled form, and 掃發票 to fill it from a paper e-invoice; on a new,
  /// still empty expense only.
  Widget _usual() {
    if (_viewing ||
        widget.entry != null ||
        widget.draft != null ||
        _f.amount != 0 ||
        _f.merchant.isNotEmpty) {
      return const SizedBox.shrink();
    }
    final usual = _ledger.usual();
    final scan = widget.scan != null;
    if (usual.isEmpty && !scan) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            if (scan) _Chip('掃發票', _scanInvoice, color: Hue.tile),
            if (usual.isNotEmpty) ...[
              if (scan) const SizedBox(width: 10),
              const Text('常用', style: mutedSmall),
            ],
            for (final e in usual) ...[
              const SizedBox(width: 6),
              _Chip(
                '${e.merchant.isEmpty ? e.category : e.merchant} '
                '${groupDigits(e.amount)}',
                () => _set(() => _f.startFrom(e)),
                color: Hue.tile,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// The categories as a grid of marks, or the parts of a split.
  Widget _categories(bool expense) {
    final parts = _f.parts;
    final used = parts == null ? 0 : parts.fold(0, (sum, p) => sum + p.$2);
    final left = _f.amount - used;
    final choices = _f.categoryChoices();
    // Five, then 更多, 代墊 and 新增 fill two rows of four.
    final shown = choices.take(5).toList();
    final lending = _f.mode == ComposeMode.lend;
    if (shown.isNotEmpty &&
        !shown.contains(_f.category) &&
        _f.category.isNotEmpty) {
      shown[shown.length - 1] = _f.category;
    }
    return FormBlock(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const IconChip(Glyph.categories),
              const SizedBox(width: 8),
              Text(
                parts == null ? '分類' : '分類 · 拆成 ${parts.length} 筆',
                style: accentLabel,
              ),
              const Spacer(),
              if (parts != null && !_viewing) ...[
                _Chip('均分', _evenly),
                const SizedBox(width: 6),
              ],
              if (expense && !_viewing && !_f.foreign && !lending)
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
                    picked: !lending && name == _f.category,
                    onTap: () => _pickCategoryName(name),
                  ),
                if (choices.length > shown.length)
                  _CategoryChoice(
                    category: const Category('更多', 'other', Hue.muted),
                    picked: false,
                    onTap: () async {
                      final picked = await _pickCategory(_f.category);
                      if (picked != null) _pickCategoryName(picked);
                    },
                  ),
                if ((!_viewing && !_f.foreign) || lending)
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
                share: _f.amount == 0 ? 0 : value / _f.amount,
                onTap: () => _editPart(i),
              ),
            if (!_viewing)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    SmallLink('＋ 再拆一個分類', _addPart, inset: 6),
                    const Spacer(),
                    Text('剩餘 ${groupDigits(left)}', style: mutedSmall),
                  ],
                ),
              ),
          ],
        ],
      ),
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
