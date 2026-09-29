part of 'main.dart';

class _BudgetScreen extends StatefulWidget {
  const _BudgetScreen({
    required this.engine,
    required this.catalog,
    required this.tags,
    required this.accounts,
    required this.privacy,
  });

  final PreviewEngine engine;
  final CategoryCatalog catalog;
  final TagCatalog? tags;
  final List<AccountSummary> accounts;
  final PrivacyMode privacy;

  @override
  State<_BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetScreenState extends State<_BudgetScreen> {
  final _month = TextEditingController();
  final _amount = TextEditingController();
  List<BudgetPlan> _plans = const [];
  final _results = <PublicId, BudgetResult>{};
  BudgetPlan? _editing;
  String _currency = 'TWD', _category = '', _account = '', _tag = '';
  bool _busy = false;
  String? _message;
  String? _pendingSignature;
  OperationId? _pendingOperation;
  PublicId? _pendingId;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month.text =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';
    if (widget.accounts.isNotEmpty) {
      _currency = widget.accounts.first.account.currency.code;
    }
    unawaited(_load());
  }

  @override
  void dispose() {
    _request++;
    _month.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final request = ++_request;
    if (!widget.engine.isUnlocked) return;
    try {
      final plans = await widget.engine.savedBudgets();
      final results = <PublicId, BudgetResult>{};
      for (final plan in plans) {
        results[plan.id] = await widget.engine.evaluateMonthlyBudget(plan);
      }
      if (!mounted || request != _request || !widget.engine.isUnlocked) return;
      setState(() {
        _plans = plans;
        _results
          ..clear()
          ..addAll(results);
      });
    } catch (_) {
      if (mounted && request == _request && widget.engine.isUnlocked) {
        setState(() => _message = '預算讀取失敗；帳本沒有被修改。');
      }
    }
  }

  OperationId _operationFor(String signature) {
    if (_pendingSignature != signature) {
      _pendingSignature = signature;
      _pendingOperation = OperationId(PublicId.generate());
      _pendingId = PublicId.generate();
    }
    return _pendingOperation!;
  }

  void _reset() {
    _editing = null;
    _amount.clear();
    _category = _account = _tag = '';
    _pendingSignature = null;
    _pendingOperation = null;
    _pendingId = null;
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy || !widget.engine.isUnlocked) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
      if (!mounted || !widget.engine.isUnlocked) return;
      setState(_reset);
      await _load();
    } catch (_) {
      if (mounted && widget.engine.isUnlocked) {
        setState(() => _message = '預算未保存。請檢查金額、月份與條件後重試。');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() => _run(() async {
    if (widget.privacy == PrivacyMode.hidden) throw const FormatException();
    final match = RegExp(r'^(\d{4})-(0[1-9]|1[0-2])$')
        .firstMatch(_month.text.trim());
    if (match == null) throw const FormatException('Invalid month');
    final year = int.parse(match.group(1)!);
    if (year < 1) throw const FormatException('Invalid year');
    final currency =
        widget.accounts
            .map((a) => a.account.currency)
            .where((c) => c.code == _currency)
            .firstOrNull ??
        (_editing?.limit.currency.code == _currency
            ? _editing!.limit.currency
            : throw const FormatException('Unknown currency'));
    final limit = Money.parse(currency, _amount.text.trim());
    final signature = [
      'save',
      _editing?.id.value ?? '',
      _editing?.version ?? 0,
      _month.text.trim(),
      _currency,
      limit.minorUnits,
      _category,
      _account,
      _tag,
    ].join('|');
    final operation = _operationFor(signature);
    final plan = BudgetPlan(
      id: _editing?.id ?? _pendingId!,
      workspace: widget.engine.workspace,
      month: ReportMonth(year, int.parse(match.group(2)!)),
      limit: limit,
      version: (_editing?.version ?? 0) + 1,
      categoryId: _category.isEmpty ? null : PublicId.parse(_category),
      accountIds: _account.isEmpty ? const {} : {PublicId.parse(_account)},
      tagIds: _tag.isEmpty ? const {} : {PublicId.parse(_tag)},
      warningPercent: _editing?.warningPercent ?? 80,
    );
    await widget.engine.saveBudget(plan, operation);
  });

  Future<void> _remove(BudgetPlan plan) async {
    if (_busy || widget.privacy == PrivacyMode.hidden) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('刪除月預算？'),
        content: const Text('這會停止顯示此預算；歷史版本仍保留在加密帳本與備份中。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('確認刪除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || !widget.engine.isUnlocked) return;
    await _run(() async {
      final operation = _operationFor(
        'delete|${plan.id.value}|${plan.version}',
      );
      await widget.engine.saveBudget(
        BudgetPlan(
          id: plan.id,
          workspace: plan.workspace,
          month: plan.month,
          limit: plan.limit,
          version: plan.version + 1,
          categoryId: plan.categoryId,
          accountIds: plan.accountIds,
          tagIds: plan.tagIds,
          warningPercent: plan.warningPercent,
        ),
        operation,
        deleted: true,
      );
    });
  }

  void _edit(BudgetPlan plan) {
    if (plan.accountIds.length > 1 || plan.tagIds.length > 1) {
      setState(() => _message = '此預算包含多個篩選條件，暫不提供簡易編輯。');
      return;
    }
    setState(() {
      _editing = plan;
      _month.text = plan.month.toString();
      _amount.text = plan.limit.majorText;
      _currency = plan.limit.currency.code;
      _category = plan.categoryId?.value ?? '';
      _account = plan.accountIds.firstOrNull?.value ?? '';
      _tag = plan.tagIds.firstOrNull?.value ?? '';
      _pendingSignature = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final enabled =
        !_busy &&
        widget.engine.isUnlocked &&
        widget.privacy == PrivacyMode.visible;
    final currencies =
        widget.accounts.map((a) => a.account.currency.code).toSet().toList()
          ..sort();
    if (_editing case final plan?) {
      if (!currencies.contains(plan.limit.currency.code)) {
        currencies.add(plan.limit.currency.code);
      }
    }
    final categories = widget.catalog.categories
        .where((c) => c.kind == CategoryKind.expense && !c.archived)
        .toList();
    final tags = widget.tags?.tags.where((t) => !t.archived).toList() ?? [];
    if (_category.isNotEmpty &&
        !categories.any((category) => category.id.value == _category)) {
      categories.addAll(
        widget.catalog.categories.where(
          (category) => category.id.value == _category,
        ),
      );
    }
    if (_tag.isNotEmpty && !tags.any((tag) => tag.id.value == _tag)) {
      tags.addAll(
        widget.tags?.tags.where((tag) => tag.id.value == _tag) ?? const [],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('月預算', style: Theme.of(context).textTheme.headlineSmall),
        const Text('只計同幣別淨支出；退款扣回，轉帳本金不計入。其他幣別會明示略過。'),
        if (_message != null) Text(_message!, key: const Key('budget-message')),
        if (_busy) const LinearProgressIndicator(),
        for (final plan in _plans) ...[
          const Divider(),
          Text(
            '${plan.month} · ${plan.limit.currency.code} · ${plan.categoryId == null ? '全部支出' : widget.catalog.get(plan.categoryId!).name}',
          ),
          MoneyView(
            money: plan.limit,
            privacy: widget.privacy,
            kind: MoneyKind.transaction,
          ),
          if (_results[plan.id] case final result?) ...[
            FinancialSummary(
              title: '已用',
              subtitle: result.atWarning ? '已達提醒門檻' : '本月淨支出',
              money: result.spent,
              privacy: widget.privacy,
              kind: MoneyKind.transaction,
              moneyKey: ValueKey('budget-spent-${plan.id.value}'),
            ),
            FinancialSummary(
              title: '剩餘',
              subtitle: result.overLimit ? '已超出預算' : '可用額度',
              money: result.remaining,
              privacy: widget.privacy,
              kind: MoneyKind.transaction,
              moneyKey: ValueKey('budget-remaining-${plan.id.value}'),
            ),
            if (result.otherCurrencyFacts > 0)
              Text('另有 ${result.otherCurrencyFacts} 筆不同幣別支出未換算。'),
          ],
          Row(
            children: [
              TextButton(
                onPressed: enabled ? () => _edit(plan) : null,
                child: const Text('修改'),
              ),
              TextButton(
                onPressed: enabled ? () => _remove(plan) : null,
                child: const Text('刪除'),
              ),
            ],
          ),
        ],
        const Divider(),
        Text(
          _editing == null ? '新增預算' : '修改預算',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        if (widget.privacy == PrivacyMode.hidden)
          const Text('先顯示金額，才能設定預算。')
        else ...[
          TextField(
            key: const Key('budget-month'),
            controller: _month,
            enabled: enabled,
            decoration: const InputDecoration(labelText: '月份（YYYY-MM）'),
          ),
          DropdownButtonFormField<String>(
            key: ValueKey('budget-currency-$_currency'),
            initialValue: currencies.contains(_currency) ? _currency : null,
            decoration: const InputDecoration(labelText: '幣別'),
            items: [
              for (final code in currencies)
                DropdownMenuItem(value: code, child: Text(code)),
            ],
            onChanged: enabled
                ? (value) => setState(() => _currency = value!)
                : null,
          ),
          TextField(
            key: const Key('budget-limit'),
            controller: _amount,
            enabled: enabled,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: '預算上限'),
          ),
          DropdownButtonFormField<String>(
            key: ValueKey('budget-category-$_category'),
            initialValue: _category,
            decoration: const InputDecoration(labelText: '分類'),
            items: [
              const DropdownMenuItem(value: '', child: Text('全部支出')),
              for (final c in categories)
                DropdownMenuItem(
                  value: c.id.value,
                  child: Text(c.archived ? '${c.name}（已封存）' : c.name),
                ),
            ],
            onChanged: enabled
                ? (value) => setState(() => _category = value!)
                : null,
          ),
          ExpansionTile(
            title: const Text('帳戶與標籤篩選'),
            children: [
              DropdownButtonFormField<String>(
                key: ValueKey('budget-account-$_account'),
                initialValue: _account,
                decoration: const InputDecoration(labelText: '帳戶'),
                items: [
                  const DropdownMenuItem(value: '', child: Text('所有帳戶')),
                  for (final a in widget.accounts)
                    DropdownMenuItem(
                      value: a.account.id.value,
                      child: Text(a.account.name),
                    ),
                  if (_account.isNotEmpty &&
                      !widget.accounts.any(
                        (a) => a.account.id.value == _account,
                      ))
                    DropdownMenuItem(
                      value: _account,
                      child: const Text('原帳戶（已隱藏）'),
                    ),
                ],
                onChanged: enabled
                    ? (value) => setState(() => _account = value!)
                    : null,
              ),
              DropdownButtonFormField<String>(
                key: ValueKey('budget-tag-$_tag'),
                initialValue: _tag,
                decoration: const InputDecoration(labelText: '標籤'),
                items: [
                  const DropdownMenuItem(value: '', child: Text('所有標籤')),
                  for (final tag in tags)
                    DropdownMenuItem(
                      value: tag.id.value,
                      child: Text(tag.archived ? '${tag.name}（已封存）' : tag.name),
                    ),
                ],
                onChanged: enabled
                    ? (value) => setState(() => _tag = value!)
                    : null,
              ),
            ],
          ),
          FilledButton(
            key: const Key('budget-save'),
            onPressed: enabled && currencies.isNotEmpty ? _save : null,
            child: Text(_editing == null ? '保存預算' : '保存修改'),
          ),
          if (_editing != null)
            TextButton(
              onPressed: enabled ? () => setState(_reset) : null,
              child: const Text('取消修改'),
            ),
        ],
      ],
    );
  }
}
