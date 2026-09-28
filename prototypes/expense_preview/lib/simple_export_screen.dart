part of 'main.dart';

extension _SimpleExportScreen on _PreviewHomeState {
  void _clearSimpleExport() {
    _simpleExportSelected = false;
    _simpleExportFormat = null;
    _simpleExportReview = null;
  }

  Future<void> _chooseSimpleExport(String format) => _perform(() async {
    final chosen = await widget.documents.chooseSimpleExport(format);
    if (!mounted || !chosen) return;
    _updateSimpleExport(() {
      _clearSimpleExport();
      _simpleExportSelected = true;
      _simpleExportFormat = format;
      _page = _engine!.isUnlocked ? _Page.simpleExport : _Page.locked;
    });
  });

  Future<void> _reviewSimpleExport() => _perform(() async {
    final epoch = _viewEpoch;
    final review = await _engine!.reviewSimpleExport();
    if (!mounted || epoch != _viewEpoch || !_engine!.isUnlocked) return;
    _updateSimpleExport(() => _simpleExportReview = review);
  });

  Future<void> _saveSimpleExport() => _perform(() async {
    final review = _simpleExportReview!;
    final format = _simpleExportFormat!;
    final epoch = _viewEpoch;
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('確認儲存未加密交換檔'),
        content: Text(
          '只匯出 ${review.includedCount} 筆普通收支；略過 '
          '${review.openingCount} 筆期初及 ${review.unsupportedCount} 筆其他交易。'
          '分類、標籤、商家、帳戶設定、歷次備註與已刪除紀錄也不包含。'
          '檔案未加密，不能用來還原完整帳本。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('確認儲存'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted || epoch != _viewEpoch) return;
    try {
      final saved = await widget.documents.writeSimpleExport(
        format == 'csv' ? review.toCsv() : review.toJson(),
      );
      if (!saved) throw PlatformException(code: 'simple_export');
      if (!mounted || epoch != _viewEpoch || !_engine!.isUnlocked) return;
      _clearSimpleExport();
      await _refresh();
      if (mounted && epoch == _viewEpoch) {
        _updateSimpleExport(() => _message = '簡易交換檔已儲存並回讀核對；它不是完整加密備份。');
      }
    } finally {
      _simpleExportSelected = false;
      _simpleExportReview = null;
    }
  });

  List<Widget> _simpleExportContent() {
    final review = _simpleExportReview;
    return [
      Text('匯出簡易收支', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 12),
      const Text(
        '此檔未加密，只供簡易資料交換。只包含仍有效的普通收入／支出日期、金額、帳戶識別與最新備註。'
        '期初餘額、帳戶設定、分類、標籤、商家、備註修訂歷史、已刪除紀錄、轉帳、退款、撤銷與其他複雜交易不在此格式內。'
        '完整還原請使用加密備份。',
      ),
      const SizedBox(height: 16),
      if (!_simpleExportSelected) ...[
        _button('選擇 JSON 儲存位置', () => _chooseSimpleExport('json')),
        _button('選擇 CSV 儲存位置', () => _chooseSimpleExport('csv')),
      ] else if (review == null)
        _button('檢查將匯出的交易', _reviewSimpleExport),
      if (review != null) ...[
        const Divider(),
        Text('將匯出 ${review.includedCount} 筆普通收支。'),
        Text(
          '略過 ${review.openingCount} 筆期初與 '
          '${review.unsupportedCount} 筆其他交易；分類、標籤、商家等附加資料不包含。',
        ),
        if (_privacy == PrivacyMode.hidden) const Text('金額已遮蔽；請先顯示金額，再確認儲存。'),
        _button(
          '確認儲存 ${_simpleExportFormat!.toUpperCase()} 交換檔',
          _privacy == PrivacyMode.visible ? _saveSimpleExport : null,
        ),
      ],
      if (_simpleExportSelected) const Text('若取消，系統選檔器已建立的空白檔可能需要自行刪除。'),
      _back(),
    ];
  }
}
