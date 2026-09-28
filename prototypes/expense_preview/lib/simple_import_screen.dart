part of 'main.dart';

extension _SimpleImportScreen on _PreviewHomeState {
  void _clearSimpleImport() {
    _simpleImportSelected = false;
    _simpleImportBatch = null;
    _simpleImportReview = null;
    _simpleImportMapping.clear();
  }

  Future<void> _chooseSimpleImport() => _perform(() async {
    final chosen = await widget.documents.chooseSimpleImport();
    if (!mounted || !chosen) return;
    _updateSimpleImport(() {
      _clearSimpleImport();
      _simpleImportSelected = true;
      _page = _engine!.isUnlocked ? _Page.simpleImport : _Page.locked;
    });
  });

  Future<void> _readSimpleImport() => _perform(() async {
    final epoch = _viewEpoch;
    String? document;
    try {
      document = await widget.documents.readSimpleImport();
    } finally {
      _simpleImportSelected = false;
    }
    if (!mounted || epoch != _viewEpoch || !_engine!.isUnlocked) return;
    if (document == null) throw PreviewInvalid();
    final trimmed = document.trimLeft();
    final batch = trimmed.startsWith('{')
        ? SimpleTransactionCodec.decodeJson(document)
        : SimpleTransactionCodec.decodeCsv(document);
    if (batch.records.map((row) => row.accountId).toSet().length > 64) {
      throw const ExchangeException('too_many_source_accounts');
    }
    _updateSimpleImport(() {
      _simpleImportBatch = batch;
      _simpleImportReview = null;
      _simpleImportMapping.clear();
    });
  });

  Future<void> _reviewSimpleImport() => _perform(() async {
    final batch = _simpleImportBatch!;
    final review = await _engine!.reviewSimpleImport(
      SimpleTransactionCodec.encodeJson(batch),
      csv: false,
      accountMapping: Map.of(_simpleImportMapping),
    );
    if (mounted && _engine!.isUnlocked) {
      _updateSimpleImport(() => _simpleImportReview = review);
    }
  });

  Future<void> _confirmSimpleImport() => _perform(() async {
    final review = _simpleImportReview!;
    final epoch = _viewEpoch;
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('確認匯入收支'),
        content: Text(
          '將 ${review.preview.rows.length} 筆收入／支出寫入目前帳本。'
          '相同來源會略過，內容衝突會整批拒絕。此檔案不是完整備份。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('確認匯入'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted || epoch != _viewEpoch) return;
    final result = await _engine!.confirmSimpleImport(review);
    _clearSimpleImport();
    await _refresh();
    if (mounted) {
      _updateSimpleImport(
        () => _message =
            '匯入完成：新增 ${result.inserted} 筆，略過重複 ${result.replayed} 筆。',
      );
    }
  });

  String _simpleAmount(Currency currency, BigInt units) {
    final divisor = BigInt.from(10).pow(currency.scale);
    final whole = units ~/ divisor;
    if (currency.scale == 0) return '${currency.code} $whole';
    final fraction = (units % divisor).toString().padLeft(currency.scale, '0');
    return '${currency.code} $whole.$fraction';
  }

  List<Widget> _simpleImportContent() {
    final batch = _simpleImportBatch;
    final review = _simpleImportReview;
    final sources = batch?.records.map((row) => row.accountId).toSet().toList()
      ?..sort((a, b) => a.value.compareTo(b.value));
    return [
      Text('匯入簡易收支', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 12),
      const Text('僅接受 V2 簡易 JSON／CSV 的一般收入與支出；轉帳、退款、分類等資料不在此格式。此檔案不能取代加密備份。'),
      const SizedBox(height: 16),
      if (_simpleImportSelected)
        _button('讀取所選檔案', _readSimpleImport)
      else if (batch == null)
        _button('選取 JSON／CSV 檔案', _chooseSimpleImport),
      if (batch != null) ...[
        Text('檔案共有 ${batch.records.length} 筆；請逐一指定目的帳戶。'),
        const SizedBox(height: 12),
        for (final source in sources!)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: DropdownButtonFormField<PublicId>(
              key: ValueKey('simple-account-${source.value}'),
              isExpanded: true,
              initialValue: _simpleImportMapping[source],
              decoration: InputDecoration(
                labelText: '來源帳戶 ${source.value.substring(0, 8)}… 對應至',
              ),
              items: [
                for (final account in _accounts)
                  DropdownMenuItem(
                    value: account.account.id,
                    child: Text(
                      '${account.account.name} · ${account.account.currency.code}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: _busy
                  ? null
                  : (id) => _updateSimpleImport(() {
                      if (id == null) {
                        _simpleImportMapping.remove(source);
                      } else {
                        _simpleImportMapping[source] = id;
                      }
                      _simpleImportReview = null;
                    }),
            ),
          ),
        if (_accounts.isEmpty) const Text('請先建立可用帳戶，再匯入檔案。'),
        _button(
          '檢查對應與金額',
          _simpleImportMapping.length == sources.length
              ? _reviewSimpleImport
              : null,
        ),
      ],
      if (review != null) ...[
        const Divider(),
        Text('確認前請核對 ${review.preview.rows.length} 筆交易與逐幣別金額。'),
        if (_privacy == PrivacyMode.hidden)
          const Text('金額已遮蔽；請先點選上方顯示金額，再確認匯入。')
        else ...[
          for (final entry in review.preview.incomeUnits.entries)
            Text('收入：${_simpleAmount(entry.key, entry.value)}'),
          for (final entry in review.preview.expenseUnits.entries)
            Text('支出：${_simpleAmount(entry.key, entry.value)}'),
        ],
        const SizedBox(height: 12),
        _button(
          '確認匯入目前帳本',
          _privacy == PrivacyMode.visible ? _confirmSimpleImport : null,
        ),
      ],
      _back(),
    ];
  }
}
