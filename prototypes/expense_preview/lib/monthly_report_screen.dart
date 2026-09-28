part of 'main.dart';

enum _MonthlyView { totals, account, category, merchant }

class _MonthlyReportScreen extends StatefulWidget {
  const _MonthlyReportScreen({
    required this.engine,
    required this.initial,
    required this.catalog,
    required this.accounts,
    required this.merchants,
    required this.privacy,
    required this.onActivity,
  });

  final PreviewEngine engine;
  final MonthlyReport initial;
  final CategoryCatalog catalog;
  final List<AccountSummary> accounts;
  final MerchantCatalog? merchants;
  final PrivacyMode privacy;
  final void Function(PublicId) onActivity;

  @override
  State<_MonthlyReportScreen> createState() => _MonthlyReportScreenState();
}

class _MonthlyReportScreenState extends State<_MonthlyReportScreen> {
  late MonthlyReport _report = widget.initial;
  bool _busy = false;
  String? _errorText;
  int _visible = 30, _request = 0;
  _MonthlyView _view = _MonthlyView.totals;
  MonthlyCategorySummary? _selectedCategory;
  MonthlyMerchantSummary? _selectedMerchant;
  MonthlyAccountSummary? _selectedAccount;

  @override
  void dispose() {
    _request++;
    super.dispose();
  }

  ReportMonth? _adjacent(int offset) {
    final index =
        (_report.month.year - 1) * 12 + _report.month.month - 1 + offset;
    if (index < 0 || index >= 9999 * 12) return null;
    return ReportMonth(index ~/ 12 + 1, index % 12 + 1);
  }

  Future<void> _change(int offset) async {
    if (_busy || !widget.engine.isUnlocked) return;
    final month = _adjacent(offset);
    if (month == null) return;
    final request = ++_request;
    setState(() {
      _busy = true;
      _errorText = null;
    });
    try {
      final next = await widget.engine.monthlyReport(month);
      if (!mounted || request != _request || !widget.engine.isUnlocked) return;
      setState(() {
        _report = next;
        _visible = 30;
        _selectedCategory = null;
        _selectedMerchant = null;
        _selectedAccount = null;
      });
    } on MoneyException {
      if (mounted && request == _request && widget.engine.isUnlocked) {
        setState(() => _errorText = '該月份合計超過可表示範圍，已保留目前報表。');
      }
    } catch (_) {
      if (mounted && request == _request && widget.engine.isUnlocked) {
        setState(() => _errorText = '讀取月份失敗；帳本沒有被修改。');
      }
    } finally {
      if (mounted && request == _request) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final facts = [for (final summary in _report.currencies) ...summary.facts]
      ..sort((a, b) {
        final date = b.date.compareTo(a.date);
        return date != 0 ? date : b.id.value.compareTo(a.id.value);
      });
    final enabled = !_busy && widget.engine.isUnlocked;
    final categoryFacts =
        _selectedCategory?.facts ?? const <MonthlyCategoryFact>[];
    final merchantFacts = _selectedMerchant?.facts ?? const <MonthlyFact>[];
    final accountFacts = _selectedAccount?.facts ?? const <MonthlyFact>[];
    String categoryName(PublicId? id) {
      if (id == null) return '未分類（含轉帳費用）';
      final row = widget.catalog.categories
          .where((c) => c.id == id)
          .firstOrNull;
      return row == null
          ? '分類資料缺失：${id.value}'
          : _categoryLabel(widget.catalog, row);
    }

    String merchantName(PublicId? id) {
      if (id == null) return '未指定商家（含轉帳費用）';
      final row = widget.merchants?.merchants
          .where((m) => m.id == id)
          .firstOrNull;
      return row == null
          ? '商家資料缺失：${id.value}'
          : _merchantLabel(widget.merchants!, row);
    }

    String accountName(PublicId? id) {
      if (id == null) return '帳戶參照缺失';
      final row = widget.accounts.where((a) => a.account.id == id).firstOrNull;
      return row == null
          ? '帳戶資料缺失：${id.value}'
          : '${row.account.name}（帳戶幣別 ${row.account.currency.code}）';
    }

    return Column(
      key: const Key('monthly-report-screen'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('月收支', style: Theme.of(context).textTheme.headlineSmall),
        const Text('逐幣別呈現已入帳的收入與淨支出；轉帳本金、期初不列入，手續費列支出。'),
        Column(
          children: [
            Text(_report.month.toString()),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  onPressed: enabled && _adjacent(-1) != null
                      ? () => _change(-1)
                      : null,
                  tooltip: '上個月',
                  icon: const Icon(Icons.chevron_left),
                ),
                IconButton(
                  onPressed: enabled && _adjacent(1) != null
                      ? () => _change(1)
                      : null,
                  tooltip: '下個月',
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ],
        ),
        if (_busy) const LinearProgressIndicator(),
        if (_errorText != null)
          Semantics(liveRegion: true, child: Text(_errorText!)),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<_MonthlyView>(
            segments: [
              const ButtonSegment(
                value: _MonthlyView.totals,
                label: Text('月收支'),
              ),
              const ButtonSegment(
                value: _MonthlyView.account,
                label: Text('帳戶'),
              ),
              const ButtonSegment(
                value: _MonthlyView.category,
                label: Text('分類'),
              ),
              if (widget.merchants != null)
                const ButtonSegment(
                  value: _MonthlyView.merchant,
                  label: Text('商家'),
                ),
            ],
            selected: {_view},
            onSelectionChanged: enabled
                ? (value) => setState(() {
                    _view = value.single;
                    _selectedCategory = null;
                    _selectedMerchant = null;
                    _selectedAccount = null;
                    _visible = 30;
                  })
                : null,
          ),
        ),
        if (_report.currencies.isEmpty) const Text('這個月沒有影響收入或支出的交易。'),
        if (_view == _MonthlyView.account) ...[
          const Text('依交易的主要帳戶歸屬收支；顯示的是報表幣別，跨幣退款可能不同於收款帳戶幣別。轉帳本金與期初不列收支。'),
          for (final summary in _report.accounts)
            Padding(
              key: ValueKey(
                'account-report-${summary.currency.code}-${summary.accountId?.value ?? 'none'}',
              ),
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${accountName(summary.accountId)} · 報表 ${summary.currency.code}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (summary.income.minorUnits != BigInt.zero)
                    FinancialSummary(
                      title: '收入',
                      subtitle: summary.currency.code,
                      money: summary.income,
                      privacy: widget.privacy,
                      kind: MoneyKind.transaction,
                      moneyKey: ValueKey(
                        'account-income-${summary.currency.code}-${summary.accountId?.value ?? 'none'}',
                      ),
                    ),
                  if (summary.expense.minorUnits != BigInt.zero)
                    FinancialSummary(
                      title: '淨支出',
                      subtitle: summary.currency.code,
                      money: summary.expense,
                      privacy: widget.privacy,
                      kind: MoneyKind.transaction,
                      moneyKey: ValueKey(
                        'account-expense-${summary.currency.code}-${summary.accountId?.value ?? 'none'}',
                      ),
                    ),
                  TextButton(
                    onPressed: enabled
                        ? () => setState(() {
                            _selectedAccount = summary;
                            _visible = 30;
                          })
                        : null,
                    child: const Text('查看帳戶明細'),
                  ),
                ],
              ),
            ),
          if (_selectedAccount != null) ...[
            const Divider(),
            Text(
              '${accountName(_selectedAccount!.accountId)}明細',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            for (final fact in accountFacts.take(_visible))
              Padding(
                key: ValueKey('account-fact-${fact.id.value}'),
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('${_kindLabel(fact.kind)} · ${fact.date}'),
                    if (fact.income.minorUnits != BigInt.zero)
                      FinancialSummary(
                        title: '收入影響',
                        subtitle: fact.currency.code,
                        money: fact.income,
                        privacy: widget.privacy,
                        kind: MoneyKind.transaction,
                        moneyKey: ValueKey(
                          'account-fact-income-${fact.id.value}',
                        ),
                      ),
                    if (fact.expense.minorUnits != BigInt.zero)
                      FinancialSummary(
                        title: '支出影響',
                        subtitle: fact.currency.code,
                        money: fact.expense,
                        privacy: widget.privacy,
                        kind: MoneyKind.transaction,
                        moneyKey: ValueKey(
                          'account-fact-expense-${fact.id.value}',
                        ),
                      ),
                    TextButton(
                      onPressed: enabled
                          ? () => widget.onActivity(fact.id)
                          : null,
                      child: const Text('查看活動'),
                    ),
                  ],
                ),
              ),
            if (accountFacts.length > _visible)
              TextButton(
                onPressed: enabled
                    ? () => setState(() => _visible += 30)
                    : null,
                child: const Text('載入更多帳戶明細'),
              ),
          ],
        ] else if (_view == _MonthlyView.category) ...[
          const Text('依交易當時的分類歸屬統計；未分類與轉帳費用另列，合併分類不改寫歷史。'),
          for (final summary in _report.categories)
            Padding(
              key: ValueKey(
                'category-report-${summary.currency.code}-${summary.categoryId?.value ?? 'none'}',
              ),
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${categoryName(summary.categoryId)} · ${summary.currency.code}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (summary.income.minorUnits != BigInt.zero)
                    FinancialSummary(
                      title: '收入',
                      subtitle: summary.currency.code,
                      money: summary.income,
                      privacy: widget.privacy,
                      kind: MoneyKind.transaction,
                      moneyKey: ValueKey(
                        'category-income-${summary.currency.code}-${summary.categoryId?.value ?? 'none'}',
                      ),
                    ),
                  if (summary.expense.minorUnits != BigInt.zero)
                    FinancialSummary(
                      title: '淨支出',
                      subtitle: summary.currency.code,
                      money: summary.expense,
                      privacy: widget.privacy,
                      kind: MoneyKind.transaction,
                      moneyKey: ValueKey(
                        'category-expense-${summary.currency.code}-${summary.categoryId?.value ?? 'none'}',
                      ),
                    ),
                  TextButton(
                    onPressed: enabled
                        ? () => setState(() {
                            _selectedCategory = summary;
                            _visible = 30;
                          })
                        : null,
                    child: const Text('查看分類明細'),
                  ),
                ],
              ),
            ),
          if (_selectedCategory != null) ...[
            const Divider(),
            Text(
              '${categoryName(_selectedCategory!.categoryId)}明細',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            for (final fact in categoryFacts.take(_visible))
              Padding(
                key: ValueKey('category-fact-${fact.source.id.value}'),
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${_kindLabel(fact.source.kind)} · ${fact.source.date}',
                    ),
                    if (fact.income.minorUnits != BigInt.zero)
                      FinancialSummary(
                        title: '收入影響',
                        subtitle: fact.source.currency.code,
                        money: fact.income,
                        privacy: widget.privacy,
                        kind: MoneyKind.transaction,
                        moneyKey: ValueKey(
                          'category-fact-income-${fact.source.id.value}',
                        ),
                      ),
                    if (fact.expense.minorUnits != BigInt.zero)
                      FinancialSummary(
                        title: '支出影響',
                        subtitle: fact.source.currency.code,
                        money: fact.expense,
                        privacy: widget.privacy,
                        kind: MoneyKind.transaction,
                        moneyKey: ValueKey(
                          'category-fact-expense-${fact.source.id.value}',
                        ),
                      ),
                    TextButton(
                      onPressed: enabled
                          ? () => widget.onActivity(fact.source.id)
                          : null,
                      child: const Text('查看活動'),
                    ),
                  ],
                ),
              ),
            if (categoryFacts.length > _visible)
              TextButton(
                onPressed: enabled
                    ? () => setState(() => _visible += 30)
                    : null,
                child: const Text('載入更多分類明細'),
              ),
          ],
        ] else if (_view == _MonthlyView.merchant) ...[
          const Text('依交易保存的商家 ID 統計；合併後仍保留原歸屬，未指定與轉帳費用另列。'),
          for (final summary in _report.merchants)
            Padding(
              key: ValueKey(
                'merchant-report-${summary.currency.code}-${summary.merchantId?.value ?? 'none'}',
              ),
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${merchantName(summary.merchantId)} · ${summary.currency.code}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (summary.income.minorUnits != BigInt.zero)
                    FinancialSummary(
                      title: '收入',
                      subtitle: summary.currency.code,
                      money: summary.income,
                      privacy: widget.privacy,
                      kind: MoneyKind.transaction,
                      moneyKey: ValueKey(
                        'merchant-income-${summary.currency.code}-${summary.merchantId?.value ?? 'none'}',
                      ),
                    ),
                  if (summary.expense.minorUnits != BigInt.zero)
                    FinancialSummary(
                      title: '淨支出',
                      subtitle: summary.currency.code,
                      money: summary.expense,
                      privacy: widget.privacy,
                      kind: MoneyKind.transaction,
                      moneyKey: ValueKey(
                        'merchant-expense-${summary.currency.code}-${summary.merchantId?.value ?? 'none'}',
                      ),
                    ),
                  TextButton(
                    onPressed: enabled
                        ? () => setState(() {
                            _selectedMerchant = summary;
                            _visible = 30;
                          })
                        : null,
                    child: const Text('查看商家明細'),
                  ),
                ],
              ),
            ),
          if (_selectedMerchant != null) ...[
            const Divider(),
            Text(
              '${merchantName(_selectedMerchant!.merchantId)}明細',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            for (final fact in merchantFacts.take(_visible))
              Padding(
                key: ValueKey('merchant-fact-${fact.id.value}'),
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('${_kindLabel(fact.kind)} · ${fact.date}'),
                    if (fact.income.minorUnits != BigInt.zero)
                      FinancialSummary(
                        title: '收入影響',
                        subtitle: fact.currency.code,
                        money: fact.income,
                        privacy: widget.privacy,
                        kind: MoneyKind.transaction,
                        moneyKey: ValueKey(
                          'merchant-fact-income-${fact.id.value}',
                        ),
                      ),
                    if (fact.expense.minorUnits != BigInt.zero)
                      FinancialSummary(
                        title: '支出影響',
                        subtitle: fact.currency.code,
                        money: fact.expense,
                        privacy: widget.privacy,
                        kind: MoneyKind.transaction,
                        moneyKey: ValueKey(
                          'merchant-fact-expense-${fact.id.value}',
                        ),
                      ),
                    TextButton(
                      onPressed: enabled
                          ? () => widget.onActivity(fact.id)
                          : null,
                      child: const Text('查看活動'),
                    ),
                  ],
                ),
              ),
            if (merchantFacts.length > _visible)
              TextButton(
                onPressed: enabled
                    ? () => setState(() => _visible += 30)
                    : null,
                child: const Text('載入更多商家明細'),
              ),
          ],
        ] else ...[
          for (final summary in _report.currencies)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    summary.currency.code,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  FinancialSummary(
                    title: '收入',
                    subtitle: '含收入撤銷',
                    money: summary.income,
                    privacy: widget.privacy,
                    kind: MoneyKind.transaction,
                    moneyKey: ValueKey(
                      'report-income-${summary.currency.code}',
                    ),
                  ),
                  FinancialSummary(
                    title: '淨支出',
                    subtitle: '退款與撤銷在當月沖減',
                    money: summary.expense,
                    privacy: widget.privacy,
                    kind: MoneyKind.transaction,
                    moneyKey: ValueKey(
                      'report-expense-${summary.currency.code}',
                    ),
                  ),
                  FinancialSummary(
                    title: '收支差額',
                    subtitle: '僅此幣別，不含估值',
                    money: summary.net,
                    privacy: widget.privacy,
                    kind: MoneyKind.transaction,
                    moneyKey: ValueKey('report-net-${summary.currency.code}'),
                  ),
                ],
              ),
            ),
          const Divider(),
          Text('明細', style: Theme.of(context).textTheme.titleLarge),
          for (final fact in facts.take(_visible))
            Padding(
              key: ValueKey('report-fact-${fact.id.value}'),
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('${_kindLabel(fact.kind)} · ${fact.date}'),
                  if (fact.income.minorUnits != BigInt.zero)
                    FinancialSummary(
                      title: '收入影響',
                      subtitle: fact.currency.code,
                      money: fact.income,
                      privacy: widget.privacy,
                      kind: MoneyKind.transaction,
                      moneyKey: ValueKey('report-fact-income-${fact.id.value}'),
                    ),
                  if (fact.expense.minorUnits != BigInt.zero)
                    FinancialSummary(
                      title: '支出影響',
                      subtitle: fact.currency.code,
                      money: fact.expense,
                      privacy: widget.privacy,
                      kind: MoneyKind.transaction,
                      moneyKey: ValueKey(
                        'report-fact-expense-${fact.id.value}',
                      ),
                    ),
                  TextButton(
                    onPressed: enabled
                        ? () => widget.onActivity(fact.id)
                        : null,
                    child: const Text('查看活動'),
                  ),
                ],
              ),
            ),
          if (facts.length > _visible)
            TextButton(
              onPressed: enabled ? () => setState(() => _visible += 30) : null,
              child: const Text('載入更多報表明細'),
            ),
        ],
      ],
    );
  }
}
