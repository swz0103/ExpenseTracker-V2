part of 'main.dart';

extension _RefundEntry on _PreviewHomeState {
  bool get _cardRefund =>
      _refund != null &&
      _accounts.any(
        (row) =>
            row.account.id == _refund!.originalAccountId &&
            row.account.kind == AccountKind.creditCard,
      );

  bool get _foreignRefund =>
      _refund != null &&
      _sourceCurrency != null &&
      _sourceCurrency != _refund!.originalAmount.currency;

  Future<void> _startRefund(PublicId original) => _perform(() async {
    await _refresh();
    if (_entryDraft != null || _draftUnreadable) throw DraftNeedsResolution();
    final status = await _engine!.refundStatus(original);
    final sourceIsCard = _accounts.any(
      (row) =>
          row.account.id == status.originalAccountId &&
          row.account.kind == AccountKind.creditCard,
    );
    if (sourceIsCard && !_engine!.capabilities.cardAuthorizations) {
      throw PreviewInvalid();
    }
    if (!mounted || !_engine!.isUnlocked) return;
    if (status.budget.remaining.minorUnits == BigInt.zero) {
      throw const LedgerException(LedgerError.refundLimit);
    }
    if (status.budget.allocations.length > EntryFields.maxSplits) {
      throw PreviewInvalid();
    }
    _edit(_Page.posting);
    _changeSplit(() {
      _refund = status;
      _income = false;
      if (_accounts.any(
        (a) =>
            a.account.id == status.originalAccountId &&
            (a.account.state == AccountState.active ||
                (sourceIsCard && a.account.kind == AccountKind.creditCard)),
      )) {
        _accountId = status.originalAccountId;
      }
      _splitRows.addAll(
        status.budget.allocations.map((a) => _SplitRow(a.categoryId, '0')),
      );
    });
  });

  Future<void> _resumeRefund(EntryDraft saved) async {
    final status = await _engine!.refundStatus(saved.fields.refundOf!);
    final sourceIsCard = _accounts.any(
      (row) =>
          row.account.id == status.originalAccountId &&
          row.account.kind == AccountKind.creditCard,
    );
    if (!mounted || !_engine!.isUnlocked) return;
    _edit(_Page.posting);
    final fields = saved.fields;
    _changeSplit(() {
      _refund = status;
      _income = false;
      _entryDraft = saved;
      _draftSaveError = null;
      _accountId =
          _accounts.any(
            (a) =>
                a.account.id == fields.accountId &&
                (a.account.state == AccountState.active ||
                    (sourceIsCard && a.account.kind == AccountKind.creditCard)),
          )
          ? fields.accountId
          : null;
      _amount.text = fields.amount;
      _date.text = fields.date;
      _received.text = fields.received ?? '';
      _splitRows.addAll(
        fields.splits.map((r) => _SplitRow(r.categoryId, r.amount)),
      );
      _message = '已恢復退款草稿；原支出與分類歸屬保持不變。';
    });
  }

  List<Widget> _refundInputs() {
    final status = _refund!, currency = status.originalAmount.currency;
    final enabled = !_busy && !_postingFrozen;
    return [
      Text('記錄退款', style: Theme.of(context).textTheme.headlineSmall),
      Text('原支出日期：${status.budget.originalDate}'),
      FinancialSummary(
        title: '原支出',
        subtitle: '',
        moneyKey: const Key('refund-original'),
        money: status.originalAmount,
        privacy: _privacy,
        kind: MoneyKind.transaction,
      ),
      FinancialSummary(
        title: '剩餘可退',
        subtitle: '',
        moneyKey: const Key('refund-remaining'),
        money: status.budget.remaining,
        privacy: _privacy,
        kind: MoneyKind.transaction,
      ),
      const Text('退款在本次日期沖減原支出，並沿用原分類、標籤與商家。'),
      const SizedBox(height: 14),
      if (_cardRefund)
        Text(
          '退款退回原信用卡：${_accountName(status.originalAccountId)}。退款按實際入帳日沖減支出；已確認的發卡行帳單及繳款分配不會自動改寫。',
        )
      else
        DropdownButtonFormField<PublicId>(
          key: ValueKey('refund-account-$_accountId'),
          initialValue: _accountId,
          decoration: const InputDecoration(labelText: '退款入帳帳戶'),
          isExpanded: true,
          items: [
            for (final s in _accounts.where(
              (s) => s.account.state == AccountState.active,
            ))
              DropdownMenuItem(
                value: s.account.id,
                child: Text('${s.account.name} · ${s.account.currency.code}'),
              ),
          ],
          onChanged: !enabled
              ? null
              : (id) => _changeSplit(() {
                  _accountId = id;
                  _received.clear();
                  _queueDraft();
                }),
        ),
      const SizedBox(height: 14),
      _amountField('原幣退款金額（正數）', currency),
      if (_foreignRefund) ...[
        AmountInputField(
          controller: _received,
          label: '實際收到金額（正數）',
          currency: _sourceCurrency,
          enabled: enabled,
          onChanged: _queueDraft,
        ),
        const Text('原幣金額控制可退上限；帳戶只增加實際收到的金額。'),
      ],
      _dateField(),
      for (var i = 0; i < _splitRows.length; i++) ...[
        Text(
          _splitRows[i].category == null
              ? '原分類'
              : _categoryLabel(
                  _catalog!,
                  _catalog!.get(_splitRows[i].category!),
                ),
        ),
        AmountInputField(
          controller: _splitRows[i].amount,
          label: '分類退款金額 ${i + 1}（可為 0）',
          currency: currency,
          enabled: enabled,
          onChanged: _queueDraft,
        ),
      ],
      if (_splitRows.isNotEmpty) const Text('各分類退款合計須等於原幣退款金額；本次不退的分類填 0。'),
      OutlinedButton(
        onPressed: !enabled
            ? null
            : () => _changeSplit(() {
                _amount.text = status.budget.remaining.majorText;
                final amounts = {
                  for (final a in status.budget.allocations)
                    a.categoryId: a.amount.majorText,
                };
                for (final row in _splitRows) {
                  row.amount.text = amounts[row.category] ?? '0';
                }
                _queueDraft();
              }),
        child: const Text('填入剩餘全額'),
      ),
    ];
  }

  List<Widget> _refundDetails(LedgerEntry entry) => [
    if (entry.refunded!.currency != entry.amount.currency)
      FinancialSummary(
        title: '原幣沖回',
        subtitle: '',
        moneyKey: const Key('refund-denominated'),
        money: entry.refunded!,
        privacy: _privacy,
        kind: MoneyKind.transaction,
      ),
    TextButton(
      key: ValueKey('refund-source-${entry.id}'),
      onPressed: _busy
          ? null
          : () => _perform(() async {
              final status = await _engine!.refundStatus(entry.refundOf!);
              if (!mounted || !_engine!.isUnlocked) return;
              await showDialog<void>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('原支出'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${status.budget.originalDate} · ${_accountName(status.originalAccountId)}',
                      ),
                      MoneyView(
                        money: status.originalAmount,
                        privacy: _privacy,
                        kind: MoneyKind.transaction,
                      ),
                      const Text('剩餘可退'),
                      MoneyView(
                        money: status.budget.remaining,
                        privacy: _privacy,
                        kind: MoneyKind.transaction,
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('關閉'),
                    ),
                  ],
                ),
              );
            }),
      child: const Text('查看原支出'),
    ),
  ];
}
