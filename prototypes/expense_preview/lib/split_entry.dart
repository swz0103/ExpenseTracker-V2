part of 'main.dart';

final class _SplitRow {
  _SplitRow(this.category, String value)
    : amount = TextEditingController(text: value);
  PublicId? category;
  final TextEditingController amount;
}

extension _SplitEntry on _PreviewHomeState {
  void _retireSplit(_SplitRow row) {
    // Let the old field detach its listeners before disposing its controller.
    row.amount.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) => row.amount.dispose());
  }

  void _resetSplits() {
    for (final row in _splitRows) {
      _retireSplit(row);
    }
    _splitRows.clear();
    _split = false;
  }

  List<Widget> _splitInputs() => [
    const Text('每項金額都必須大於 0，合計須等於交易總額；最多 16 項。'),
    for (var i = 0; i < _splitRows.length; i++)
      Card(
        key: ObjectKey(_splitRows[i]),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<PublicId>(
                key: ValueKey(
                  'split-category-$i-${_splitRows[i].category}-$_income',
                ),
                initialValue: _splitRows[i].category,
                isExpanded: true,
                decoration: InputDecoration(labelText: '拆分分類 ${i + 1}'),
                items: [
                  for (final c in _catalog!.categories.where(
                    (c) =>
                        !c.archived &&
                        c.replacementId == null &&
                        c.kind ==
                            (_income
                                ? CategoryKind.income
                                : CategoryKind.expense) &&
                        !_splitRows.any(
                          (row) => row != _splitRows[i] && row.category == c.id,
                        ),
                  ))
                    DropdownMenuItem(
                      value: c.id,
                      child: Text(
                        _categoryLabel(_catalog!, c),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (_busy || _postingFrozen)
                    ? null
                    : (id) => _changeSplit(() {
                        _splitRows[i].category = id;
                        _queueDraft();
                      }),
              ),
              const SizedBox(height: 14),
              AmountInputField(
                controller: _splitRows[i].amount,
                label: '拆分金額 ${i + 1}',
                currency: _sourceCurrency,
                enabled: !_busy && !_postingFrozen,
                onChanged: _queueDraft,
              ),
              TextButton(
                onPressed: (_busy || _postingFrozen || _splitRows.length <= 2)
                    ? null
                    : () => _changeSplit(() {
                        _retireSplit(_splitRows.removeAt(i));
                        _queueDraft();
                      }),
                child: Text('移除拆分 ${i + 1}'),
              ),
            ],
          ),
        ),
      ),
    Text(_splitTotal(), key: const Key('split-total')),
    TextButton(
      onPressed:
          (_busy ||
              _postingFrozen ||
              _splitRows.length >= EntryFields.maxSplits)
          ? null
          : () => _changeSplit(() {
              _splitRows.add(_SplitRow(null, ''));
              _queueDraft();
            }),
      child: const Text('增加拆分'),
    ),
  ];

  String _splitTotal() {
    final currency = _sourceCurrency;
    if (currency == null) return '請先選擇帳戶。';
    try {
      final total = Money.parse(currency, _amount.text);
      var sum = BigInt.zero;
      for (final row in _splitRows) {
        final money = Money.parse(currency, row.amount.text);
        if (money.minorUnits <= BigInt.zero) return '每項拆分金額都必須大於 0。';
        sum += money.minorUnits;
      }
      final allocated = Money(currency, sum);
      final remaining = Money(currency, total.minorUnits - sum);
      return '拆分合計 ${currency.code} ${allocated.majorText} · 差額 ${currency.code} ${remaining.majorText}';
    } on MoneyException {
      return '請填妥總額與每項金額；算式需先計算並套用。';
    }
  }

  String _allocationLabel(PublicId id) {
    final rows = _entryCategories[id]!;
    if (rows.isEmpty) return '未分類';
    if (rows.length > 1) return '拆分 ${rows.length} 個分類';
    return _categoryLabel(_catalog!, _catalog!.get(rows.single.categoryId));
  }

  List<Widget> _splitDetails(PublicId id) {
    final rows = _entryCategories[id];
    if (rows == null || rows.length < 2) return const [];
    return [
      for (final row in rows)
        Padding(
          padding: const EdgeInsets.only(top: 8, left: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_categoryLabel(_catalog!, _catalog!.get(row.categoryId))),
              MoneyView(
                key: ValueKey('split-money-$id-${row.categoryId}'),
                money: row.amount,
                privacy: _privacy,
                kind: MoneyKind.transaction,
              ),
            ],
          ),
        ),
    ];
  }
}
