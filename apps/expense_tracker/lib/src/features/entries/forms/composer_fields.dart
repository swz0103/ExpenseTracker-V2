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
      onTap: _viewing
          ? null
          : () async {
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
      label: Words.date,
      value: _f.date == _ledger.today ? '今天 $day' : '$day ${formatE(_f.date)}',
      onTap: _viewing ? null : _pickDate,
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
                ? UsualFields(this).spending()
                : CategoryFields(this).splitState(),
          ),
          if (parts != null)
            AllocationBar(
              parts: [
                for (final (name, value) in parts)
                  (_ledger.category(name), value),
              ],
              onTap: _editPart,
            ),
          CategoryFields(this).row(expense: expense),
          _pair(_accountPick(expense ? '付款帳戶' : '收款帳戶'), _datePick()),
          if (_f.foreign) CurrencyFields(this).home(),
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
          _hero(under: UsualFields(this).transfers()),
          _ends(),
          if (_f.crossing) CurrencyFields(this).received(),
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
                      label: Words.fee,
                      value: '手續費 ${groupDigits(_f.fee)}',
                      valueColor: _f.fee > 0
                          ? AppColors.negative
                          : AppColors.ink,
                      onTap: () async {
                        final value = await _ask(Words.fee, _f.fee);
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
}
