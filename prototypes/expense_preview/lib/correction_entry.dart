part of 'main.dart';

extension _CorrectionEntry on _PreviewHomeState {
  Future<void> _startCorrection(PublicId original) => _perform(() async {
    await _refresh();
    if (_entryDraft != null || _draftUnreadable) throw DraftNeedsResolution();
    final source = await _engine!.reversalSource(original);
    if (!mounted || !_engine!.isUnlocked) return;
    final p = source.posting;
    _edit(_Page.posting, transfer: p.kind == PostingKind.transfer);
    _changeSplit(() {
      _correction = source;
      _income = p.kind == PostingKind.income;
      _date.text = p.date.toString();
      _accountId =
          _accounts.any(
            (a) =>
                a.account.id == p.legs.first.account.id &&
                a.account.state == AccountState.active,
          )
          ? p.legs.first.account.id
          : null;
      _amount.text =
          (p.kind == PostingKind.transfer
                  ? -p.legs.first.amount
                  : p.kind == PostingKind.income
                  ? p.reportIncome
                  : p.reportExpense)
              .majorText;
      if (p.kind == PostingKind.transfer) {
        _destinationId =
            _destinations.any((a) => a.account.id == p.legs[1].account.id)
            ? p.legs[1].account.id
            : null;
        _fee.text = p.reportExpense.majorText;
        _received.text = p.conversion == null ? '' : p.legs[1].amount.majorText;
      } else {
        if (p.allocations.length == 1) {
          final id = p.allocations.single.categoryId;
          if (_catalog!.categories.any(
            (c) => c.id == id && !c.archived && c.replacementId == null,
          )) {
            _categoryId = id.value;
          }
        } else if (p.allocations.length > 1) {
          _split = true;
          for (final allocation in p.allocations) {
            final id = allocation.categoryId;
            final available = _catalog!.categories.any(
              (c) => c.id == id && !c.archived && c.replacementId == null,
            );
            _splitRows.add(
              _SplitRow(available ? id : null, allocation.amount.majorText),
            );
          }
        }
        for (final tag in source.tags) {
          if (_tagCatalog?.tags.any(
                (t) => t.id == tag.id && !t.archived && t.replacementId == null,
              ) ??
              false) {
            _selectedTags.add(tag.id);
          }
        }
        final merchant = source.merchant;
        if (merchant != null &&
            (_merchantCatalog?.merchants.any(
                  (m) =>
                      m.id == merchant.id &&
                      !m.archived &&
                      m.replacementId == null,
                ) ??
                false)) {
          _merchantId = merchant.id.value;
        }
      }
      _message = '請確認替代日期、金額和歸屬；已停用的分類、標籤或商家需重新選擇。';
    });
    _queueDraft();
  });

  List<Widget> _correctionIntro() {
    final p = _correction!.posting;
    return [
      Text('更正交易', style: Theme.of(context).textTheme.headlineSmall),
      Text('原交易：${p.date} · ${_kindLabel(p.kind)}'),
      const Text('將保留原交易，完整沖回各帳戶的原金額，再新增下方替代交易。'),
      for (var i = 0; i < p.legs.length; i++)
        FinancialSummary(
          title: '${_accountName(p.legs[i].account.id)} · 原金額沖回',
          subtitle: '',
          money: -p.legs[i].amount,
          privacy: _privacy,
          kind: MoneyKind.transaction,
          moneyKey: ValueKey('correction-impact-$i'),
        ),
      const SizedBox(height: 12),
      _field('更正原因（選填）', _correctionReason, length: 256),
      const SizedBox(height: 16),
    ];
  }

  Future<bool> _confirmCorrection() async {
    final epoch = _viewEpoch;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('確認更正這筆交易？'),
        content: const Text(
          '原交易與活動紀錄會保留，系統將完整沖回原交易並新增替代交易。請先核對畫面的帳戶、日期、金額和分類。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('返回檢查'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('確認更正'),
          ),
        ],
      ),
    );
    return yes == true && mounted && epoch == _viewEpoch && _engine!.isUnlocked;
  }
}
