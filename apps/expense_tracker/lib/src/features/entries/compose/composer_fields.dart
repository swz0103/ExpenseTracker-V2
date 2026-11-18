part of 'composer.dart';

/// The form's fields, one builder each, by kind of entry. Each kind's
/// list starts at the amount (a trade's at what is traded).
extension _Fields on _ComposerState {
  /// Two cards side by side, such as the account and the day.
  Widget _pair(Widget left, Widget right) => Padding(
    padding: const EdgeInsets.only(top: Space.s3),
    child: Row(
      children: [
        Expanded(child: left),
        const SizedBox(width: Space.s2),
        Expanded(child: right),
      ],
    ),
  );

  Widget _accountPick(String label) {
    final account = _ledger.account(_f.account);
    return PickCard(
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
    final day = formatMd(_f.date);
    return PickCard(
      icon: Glyph.calendar,
      label: '日期',
      value: _f.date == _ledger.today ? '今天 $day' : '$day ${formatE(_f.date)}',
      onTap: _pickDate,
    );
  }

  /// The worth in NT$ of a foreign amount, at today's rate until typed.
  Widget _homeTile() {
    final value = _f.homeValue;
    final rate = _ledger.marketData.rates[_f.currency];
    return Padding(
      padding: const EdgeInsets.only(top: Space.s2),
      child: FigureCard(
        color: _color,
        icon: Glyph.coins,
        label: '折合台幣',
        value: value == null ? '請輸入' : groupDigits(value),
        valueColor: value == null ? Hue.hint : Hue.ink,
        size: TextSize.body,
        sub: _f.home != null || rate == null ? null : '臺銀即期買入 $rate',
        onTap: () async {
          final typed = await _ask('折合台幣', value ?? 0);
          if (typed != null) _set(() => _f.home = typed);
        },
      ),
    );
  }

  /// The note, folded to one line until opened or written in.
  Widget _noteRow() => NoteRow(
    controller: _note,
    viewing: _viewing,
    open: _f.more,
    onOpen: () => _set(() => _f.more = true),
  );

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
                ? LendFields(this).row()
                : parts == null
                ? _usual()
                : _splitState(),
          ),
          if (parts != null)
            AllocationBar(
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
              padding: const EdgeInsets.only(top: Space.s2),
              child: FigureCard(
                color: _color,
                icon: Glyph.card,
                label: '分期付款',
                value: _f.installments < 2
                    ? '不分期'
                    : installmentPlan(_f.amount, _f.installments),
                size: TextSize.body,
                onTap: _pickInstallments,
              ),
            ),
          ExtrasFields(this).build(expense: expense),
        ];
      case ComposeMode.transfer:
        return [
          _hero(under: _usualTransfers()),
          _ends(),
          if (_f.crossing) _receivedTile(),
          if (!_f.takesFee)
            Padding(
              padding: const EdgeInsets.only(top: Space.s3),
              child: _datePick(),
            )
          else
            _pair(
              _f.takesFee
                  ? PickCard(
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
        return LendFields(this).build();
      case ComposeMode.investment:
        return InvestmentFields(this).build(context);
    }
  }

  /// The two accounts of a transfer side by side, each with what it will
  /// hold afterwards, and between them the arrow that turns them round.
  Widget _ends() => TransferEnds(
    ledger: _ledger,
    from: _ledger.account(_f.account),
    to: _ledger.account(_f.to),
    amount: _f.amount,
    fromAfter: _f.fromAfter,
    toAfter: _f.toAfter,
    onPickFrom: () async {
      final picked = await _pickAccount('轉出帳戶', _f.account);
      if (picked != null) _set(() => _f.setFrom(picked));
    },
    onPickTo: () async {
      final picked = await _pickAccount('轉入帳戶', _f.to);
      if (picked != null) _set(() => _f.setTo(picked));
    },
    onSwap: () => _set(_f.swapEnds),
  );

  /// What a transfer between currencies delivers, at today's rates until
  /// typed.
  Widget _receivedTile() {
    final value = _f.receivedValue;
    return Padding(
      padding: const EdgeInsets.only(top: Space.s2),
      child: FigureCard(
        color: _color,
        icon: Glyph.coins,
        label: '轉入金額',
        value: value == null ? '請輸入' : amountIn(value, _f.toCurrency),
        valueColor: value == null ? Hue.hint : Hue.ink,
        size: TextSize.body,
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
        ? UsualChip(
            icon: Glyph.heart,
            name: income ? '對方還錢' : '代墊',
            strong: true,
            onTap: income ? () => _lend(back: true) : _pickLent,
          )
        : null;
    final usual = fresh
        ? _ledger.entryQueryService.usual(income: income)
        : const <Entry>[];
    final scan = fresh && widget.scan != null && !income;
    if (usual.isEmpty && !scan && lend == null) return null;
    return UsualRow(lead: lend, [
      if (scan) UsualChip(icon: Glyph.scan, name: '掃發票', onTap: _scanInvoice),
      for (final (e, category) in [
        for (final e in usual) (e, _ledger.category(e.category)),
      ])
        UsualChip(
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
    final usual = _ledger.entryQueryService.usualTransfers();
    if (usual.isEmpty) return null;
    return UsualRow([
      for (final e in usual)
        UsualChip(
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
    final left = _f.splitLeft;
    return BubbleRow([
      Bubble(
        left == 0
            ? '✓ 剛好分完'
            : left > 0
            ? '還剩 ${groupDigits(left)}'
            : '多了 ${groupDigits(-left)}',
        null,
        color: left == 0 ? Hue.positive.withValues(alpha: 0.14) : null,
        ink: left == 0 ? Hue.positive : Hue.negative,
      ),
      if (!_viewing && parts.isNotEmpty) Bubble('平均分配', _evenly),
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
    final (:shown, :more) = _f.categoryRow();
    final lending = _f.mode == ComposeMode.lend;
    final items = [
      for (final category in [for (final n in shown) _ledger.category(n)])
        ChoiceStripItem(
          label: category.name,
          icon: iconFor(category.icon),
          color: splitting ? shownColor(Color(category.color)) : _color,
          picked: splitting
              ? inParts.contains(category.name)
              : !lending && category.name == _f.category,
          onTap: splitting
              ? () => _set(() => _f.togglePart(category.name))
              : () => _pickCategoryName(category.name),
        ),
      if (more)
        ChoiceStripItem(
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
        ChoiceStripItem(
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
    return ChoiceStrip(
      items: items,
      pinned: canSplit
          ? ChoiceStripItem(
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
}
