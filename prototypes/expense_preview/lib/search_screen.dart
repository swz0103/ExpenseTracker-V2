part of 'main.dart';

/// Disposable, read-only search state. Leaving this page (including on lock)
/// discards both the query and the results.
class _SearchScreen extends StatefulWidget {
  const _SearchScreen({
    required this.engine,
    required this.accounts,
    required this.categories,
    required this.tags,
    required this.merchants,
    required this.privacy,
    required this.onActivity,
  });

  final PreviewEngine engine;
  final List<AccountSummary> accounts;
  final List<Category> categories;
  final List<Tag> tags;
  final List<Merchant> merchants;
  final PrivacyMode privacy;
  final void Function(PublicId) onActivity;

  @override
  State<_SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<_SearchScreen> {
  final _from = TextEditingController();
  final _through = TextEditingController();
  final _minimum = TextEditingController();
  final _maximum = TextEditingController();
  final _note = TextEditingController();
  PublicId? _account, _category, _tag, _merchant;
  Currency? _currency;
  PostingKind? _kind;
  LedgerSearchQuery? _query;
  List<LedgerEntry> _results = [];
  bool _busy = false, _searched = false, _hasMore = false;
  String? _errorText;
  int _request = 0;

  @override
  void dispose() {
    _request++;
    for (final controller in [_from, _through, _minimum, _maximum, _note]) {
      controller.dispose();
    }
    super.dispose();
  }

  BusinessDate? _date(TextEditingController input) =>
      input.text.trim().isEmpty ? null : BusinessDate.parse(input.text.trim());

  LedgerSearchQuery _buildQuery() {
    if ((_minimum.text.trim().isNotEmpty || _maximum.text.trim().isNotEmpty) &&
        _currency == null) {
      throw const FormatException('請先選擇金額的幣別。');
    }
    Money? amount(TextEditingController input) => input.text.trim().isEmpty
        ? null
        : Money.parse(_currency!, input.text.trim());
    return LedgerSearchQuery(
      from: _date(_from),
      through: _date(_through),
      accountId: _account,
      categoryId: _category,
      tagId: _tag,
      merchantId: _merchant,
      currency: _currency,
      kind: _kind,
      minAbsAmount: amount(_minimum),
      maxAbsAmount: amount(_maximum),
      noteContains: _note.text.trim().isEmpty ? null : _note.text.trim(),
    );
  }

  Future<void> _search() async {
    if (_busy || !widget.engine.isUnlocked) return;
    LedgerSearchQuery query;
    try {
      query = _buildQuery();
    } catch (_) {
      setState(() => _errorText = '請檢查日期、幣別與金額範圍；金額不可為負數。');
      return;
    }
    final request = ++_request;
    setState(() {
      _busy = true;
      _errorText = null;
      _results = [];
      _searched = false;
      _hasMore = false;
    });
    try {
      final rows = await widget.engine.searchEntries(query);
      if (!mounted || request != _request || !widget.engine.isUnlocked) return;
      setState(() {
        _query = query;
        _results = rows;
        _searched = true;
        _hasMore = rows.length == 30;
      });
    } catch (_) {
      if (mounted && request == _request && widget.engine.isUnlocked) {
        setState(() => _errorText = '搜尋失敗；帳本沒有被修改，請重試。');
      }
    } finally {
      if (mounted && request == _request) setState(() => _busy = false);
    }
  }

  Future<void> _more() async {
    if (_busy || !_hasMore || _results.isEmpty || !widget.engine.isUnlocked) {
      return;
    }
    final request = ++_request;
    setState(() {
      _busy = true;
      _errorText = null;
    });
    try {
      final rows = await widget.engine.searchEntries(
        _query!,
        before: _results.last,
      );
      if (!mounted || request != _request || !widget.engine.isUnlocked) return;
      setState(() {
        _results = [..._results, ...rows];
        _hasMore = rows.length == 30;
      });
    } catch (_) {
      if (mounted && request == _request && widget.engine.isUnlocked) {
        setState(() => _errorText = '載入失敗；既有結果仍保留，請重試。');
      }
    } finally {
      if (mounted && request == _request) setState(() => _busy = false);
    }
  }

  void _invalidate() {
    if (!_searched && _errorText == null) return;
    setState(() {
      _query = null;
      _results = [];
      _searched = false;
      _hasMore = false;
      _errorText = null;
    });
  }

  void _select(VoidCallback update) {
    setState(() {
      update();
      _query = null;
      _results = [];
      _searched = false;
      _hasMore = false;
      _errorText = null;
    });
  }

  void _clear() {
    if (_busy) return;
    _from.clear();
    _through.clear();
    _minimum.clear();
    _maximum.clear();
    _note.clear();
    setState(() {
      _account = _category = _tag = _merchant = null;
      _currency = null;
      _kind = null;
      _query = null;
      _results = [];
      _searched = false;
      _hasMore = false;
      _errorText = null;
    });
  }

  String _accountName(PublicId id) =>
      widget.accounts
          .where((row) => row.account.id == id)
          .firstOrNull
          ?.account
          .name ??
      '帳戶';

  Widget _choice<T>(
    String label,
    T? value,
    List<DropdownMenuItem<T>> items,
    ValueChanged<T?> onChanged,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label),
        DropdownButton<T>(
          value: value,
          isExpanded: true,
          hint: const Text('全部'),
          items: [
            DropdownMenuItem<T>(child: const Text('全部')),
            ...items,
          ],
          onChanged: _busy ? null : onChanged,
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final currencies =
        widget.accounts.map((row) => row.account.currency).toSet().toList()
          ..sort((a, b) => a.code.compareTo(b.code));
    final enabled = !_busy && widget.engine.isUnlocked;
    return Column(
      key: const Key('search-screen'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('搜尋交易', style: Theme.of(context).textTheme.headlineSmall),
        const Text('條件同時成立才顯示；日期與金額兩端都包含。'),
        const SizedBox(height: 16),
        BusinessDateInputField(
          controller: _from,
          label: '開始日期（YYYY-MM-DD）',
          help: '選擇開始日期',
          enabled: enabled,
          canApply: () => mounted && widget.engine.isUnlocked,
          onChanged: _invalidate,
        ),
        const SizedBox(height: 12),
        BusinessDateInputField(
          controller: _through,
          label: '結束日期（YYYY-MM-DD）',
          help: '選擇結束日期',
          enabled: enabled,
          canApply: () => mounted && widget.engine.isUnlocked,
          onChanged: _invalidate,
        ),
        const SizedBox(height: 12),
        _choice<PublicId>('帳戶', _account, [
          for (final row in widget.accounts)
            DropdownMenuItem(
              value: row.account.id,
              child: Text(row.account.name),
            ),
        ], (value) => _select(() => _account = value)),
        _choice<PublicId>('分類', _category, [
          for (final row in widget.categories)
            DropdownMenuItem(value: row.id, child: Text(row.name)),
        ], (value) => _select(() => _category = value)),
        if (widget.engine.capabilities.tags)
          _choice<PublicId>('標籤', _tag, [
            for (final row in widget.tags)
              DropdownMenuItem(value: row.id, child: Text(row.name)),
          ], (value) => _select(() => _tag = value)),
        if (widget.engine.capabilities.merchants)
          _choice<PublicId>('商家', _merchant, [
            for (final row in widget.merchants)
              DropdownMenuItem(value: row.id, child: Text(row.name)),
          ], (value) => _select(() => _merchant = value)),
        _choice<PostingKind>('種類', _kind, [
          for (final kind in PostingKind.values)
            DropdownMenuItem(value: kind, child: Text(_kindLabel(kind))),
        ], (value) => _select(() => _kind = value)),
        _choice<Currency>('幣別', _currency, [
          for (final currency in currencies)
            DropdownMenuItem(value: currency, child: Text(currency.code)),
        ], (value) => _select(() => _currency = value)),
        TextField(
          key: const Key('search-minimum'),
          controller: _minimum,
          enabled: enabled,
          onChanged: (_) => _invalidate(),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: '最低金額（原幣絕對值）'),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('search-maximum'),
          controller: _maximum,
          enabled: enabled,
          onChanged: (_) => _invalidate(),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: '最高金額（原幣絕對值）'),
        ),
        if (widget.engine.capabilities.notes) ...[
          const SizedBox(height: 12),
          TextField(
            key: const Key('search-note'),
            controller: _note,
            enabled: enabled,
            onChanged: (_) => _invalidate(),
            maxLength: 100,
            decoration: const InputDecoration(labelText: '備註包含文字'),
          ),
        ],
        const SizedBox(height: 12),
        FilledButton(
          onPressed: enabled ? _search : null,
          child: const Text('查詢'),
        ),
        TextButton(
          onPressed: enabled ? _clear : null,
          child: const Text('清除條件'),
        ),
        if (_busy) const LinearProgressIndicator(),
        if (_errorText != null)
          Semantics(liveRegion: true, child: Text(_errorText!)),
        if (_searched) ...[
          Text('結果 ${_results.length} 筆${_hasMore ? '（可載入更多）' : ''}'),
          if (_results.isEmpty) const Text('沒有符合條件的交易。'),
          for (final row in _results)
            Card(
              key: ValueKey('search-result-${row.id.value}'),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FinancialSummary(
                      title:
                          '${_kindLabel(row.kind)} · ${_accountName(row.accountId)}',
                      subtitle:
                          '${row.date}${row.destinationId == null ? '' : ' → ${_accountName(row.destinationId!)}'}',
                      money: row.amount,
                      privacy: widget.privacy,
                      kind: MoneyKind.transaction,
                      moneyKey: ValueKey('search-money-${row.id.value}'),
                    ),
                    if (row.note.text.isNotEmpty)
                      Text(
                        widget.privacy == PrivacyMode.hidden
                            ? '備註已隱藏'
                            : row.note.text,
                      ),
                    TextButton(
                      onPressed: enabled
                          ? () => widget.onActivity(row.id)
                          : null,
                      child: const Text('查看活動'),
                    ),
                  ],
                ),
              ),
            ),
          if (_hasMore)
            TextButton(
              onPressed: enabled ? _more : null,
              child: const Text('載入更多搜尋結果'),
            ),
        ],
      ],
    );
  }
}
