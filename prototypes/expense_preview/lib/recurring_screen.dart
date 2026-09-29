part of 'main.dart';

class _RecurringScreen extends StatefulWidget {
  const _RecurringScreen({
    required this.engine,
    required this.accounts,
    required this.privacy,
    this.reminder,
  });

  final PreviewEngine engine;
  final List<AccountSummary> accounts;
  final PrivacyMode privacy;
  final RecurringReminderService? reminder;

  @override
  State<_RecurringScreen> createState() => _RecurringScreenState();
}

class _RecurringScreenState extends State<_RecurringScreen> {
  final _label = TextEditingController();
  final _amount = TextEditingController();
  final _firstDate = TextEditingController();
  final _every = TextEditingController(text: '1');
  final _after = TextEditingController();
  List<RecurringTemplate> _templates = const [];
  List<RecurringCandidate> _due = const [];
  RecurringTemplate? _editing;
  PublicId? _pendingId;
  OperationId? _pendingOperation;
  String? _pendingSignature;
  final _confirmOperations =
      <String, ({PublicId eventId, OperationId operation})>{};
  final _deleteOperations = <String, OperationId>{};
  String? _account;
  RecurrenceUnit _unit = RecurrenceUnit.month;
  bool _expense = true, _busy = false;
  bool _reminderEnabled = false, _reminderBusy = false;
  String? _reminderMessage;
  String? _message;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _firstDate.text = BusinessDate(now.year, now.month, now.day).toString();
    final lastYear = DateTime(now.year - 1, now.month, now.day);
    _after.text = BusinessDate(
      lastYear.year,
      lastYear.month,
      lastYear.day,
    ).toString();
    _account = widget.accounts
        .where((row) => row.account.state == AccountState.active)
        .firstOrNull
        ?.account
        .id
        .value;
    unawaited(_load());
    if (widget.reminder != null) unawaited(_loadReminder());
  }

  @override
  void dispose() {
    _request++;
    for (final controller in [_label, _amount, _firstDate, _every, _after]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final request = ++_request;
    if (!widget.engine.isUnlocked) return;
    try {
      final after = BusinessDate.parse(_after.text.trim());
      final now = DateTime.now();
      final through = BusinessDate(now.year, now.month, now.day);
      final templates = await widget.engine.savedRecurringTemplates();
      final due = await widget.engine.dueRecurringCandidates(
        after: after,
        through: through,
      );
      if (!mounted || request != _request || !widget.engine.isUnlocked) return;
      setState(() {
        _templates = templates;
        _due = due;
        _message = null;
      });
    } catch (_) {
      if (mounted && request == _request && widget.engine.isUnlocked) {
        setState(() => _message = '候選讀取失敗。請檢查查詢起日；數量過多時可縮短期間。');
      }
    }
  }

  Future<void> _loadReminder() async {
    try {
      final enabled = await widget.reminder!.isEnabled();
      if (mounted && widget.engine.isUnlocked) {
        setState(() => _reminderEnabled = enabled);
      }
    } catch (_) {
      if (mounted && widget.engine.isUnlocked) {
        setState(() => _reminderMessage = '提醒狀態無法讀取；不影響帳本。');
      }
    }
  }

  Future<void> _setReminder(bool enabled) async {
    if (_reminderBusy || !widget.engine.isUnlocked) return;
    setState(() {
      _reminderBusy = true;
      _reminderMessage = null;
    });
    try {
      final active = await widget.reminder!.setEnabled(enabled);
      if (mounted && widget.engine.isUnlocked) {
        setState(() {
          _reminderEnabled = active;
          if (enabled && !active) {
            _reminderMessage = '系統未允許通知；請在 Android 設定開啟後重試。帳本不受影響。';
          }
        });
      }
    } catch (_) {
      if (mounted && widget.engine.isUnlocked) {
        setState(() => _reminderMessage = '提醒設定失敗；帳本不受影響。');
      }
    } finally {
      if (mounted) setState(() => _reminderBusy = false);
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

  void _resetForm() {
    _editing = null;
    _label.clear();
    _amount.clear();
    _every.text = '1';
    _unit = RecurrenceUnit.month;
    _expense = true;
    _pendingSignature = null;
    _pendingOperation = null;
    _pendingId = null;
  }

  Future<void> _run(Future<void> Function() action, String failure) async {
    if (_busy || !widget.engine.isUnlocked) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
      if (!mounted || !widget.engine.isUnlocked) return;
      await _load();
    } catch (_) {
      if (mounted && widget.engine.isUnlocked) {
        setState(() => _message = failure);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() => _run(() async {
    if (widget.privacy == PrivacyMode.hidden) throw const FormatException();
    final account = widget.accounts
        .where((row) => row.account.id.value == _account)
        .firstOrNull
        ?.account;
    if (account == null || account.state != AccountState.active) {
      throw const FormatException('Unknown account');
    }
    final parsed = Money.parse(account.currency, _amount.text.trim());
    if (parsed.minorUnits <= BigInt.zero) throw const FormatException();
    final every = int.parse(_every.text.trim());
    final firstDate = BusinessDate.parse(_firstDate.text.trim());
    final signature = [
      _editing?.id.value ?? '',
      _editing?.version ?? 0,
      _label.text.trim(),
      account.id.value,
      parsed.minorUnits,
      firstDate,
      _unit.name,
      every,
      _expense,
    ].join('|');
    final operation = _operationFor(signature);
    final template = RecurringTemplate(
      id: _editing?.id ?? _pendingId!,
      workspace: widget.engine.workspace,
      accountId: account.id,
      label: _label.text.trim(),
      amount: _expense ? -parsed : parsed,
      firstDate: firstDate,
      unit: _unit,
      every: every,
      version: (_editing?.version ?? 0) + 1,
    );
    await widget.engine.saveRecurringTemplate(template, operation);
    if (mounted) setState(_resetForm);
  }, '模板未保存；請檢查帳戶、金額、日期與週期後重試。');

  Future<void> _remove(RecurringTemplate template) async {
    if (_busy || widget.privacy == PrivacyMode.hidden) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('停用定期交易？'),
        content: const Text('尚未入帳的候選會停止顯示；已確認的帳本交易不會刪除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('確認停用'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || !widget.engine.isUnlocked) return;
    await _run(() async {
      final key = '${template.id.value}:${template.version}';
      final operation = _deleteOperations.putIfAbsent(
        key,
        () => OperationId(PublicId.generate()),
      );
      await widget.engine.saveRecurringTemplate(
        RecurringTemplate(
          id: template.id,
          workspace: template.workspace,
          accountId: template.accountId,
          label: template.label,
          amount: template.amount,
          firstDate: template.firstDate,
          unit: template.unit,
          every: template.every,
          version: template.version + 1,
        ),
        operation,
        deleted: true,
      );
      _deleteOperations.remove(key);
    }, '停用失敗；帳本沒有新增交易，請重試。');
  }

  Future<void> _confirm(RecurringCandidate candidate) async {
    if (_busy || widget.privacy == PrivacyMode.hidden) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('確認入帳？'),
        content: Text(
          '${candidate.template.label} · ${candidate.dueDate}\n'
          '只有確認後才會寫入帳本。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('確認入帳'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted || !widget.engine.isUnlocked) return;
    await _run(() async {
      final ids = _confirmOperations.putIfAbsent(
        candidate.key,
        () => (
          eventId: PublicId.generate(),
          operation: OperationId(PublicId.generate()),
        ),
      );
      await widget.engine.confirmRecurringCandidate(
        candidate,
        ids.eventId,
        ids.operation,
      );
      _confirmOperations.remove(candidate.key);
    }, '入帳未確認成功；請重新查看候選再試，不會自行重複扣款。');
  }

  void _edit(RecurringTemplate template) => setState(() {
    _editing = template;
    _label.text = template.label;
    _amount.text = template.amount.minorUnits.isNegative
        ? (-template.amount).majorText
        : template.amount.majorText;
    _firstDate.text = template.firstDate.toString();
    _every.text = template.every.toString();
    _account = template.accountId.value;
    _unit = template.unit;
    _expense = template.amount.minorUnits.isNegative;
    _pendingSignature = null;
  });

  @override
  Widget build(BuildContext context) {
    final enabled =
        !_busy &&
        widget.engine.isUnlocked &&
        widget.privacy == PrivacyMode.visible;
    final accounts = [...widget.accounts];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('定期交易', style: Theme.of(context).textTheme.headlineSmall),
        const Text('到期只列候選；逐筆確認後才入帳。'),
        if (widget.reminder != null) ...[
          SwitchListTile(
            title: const Text('每日檢查提醒'),
            subtitle: const Text('約上午 9 點提醒開啟 App 檢查；通知不含帳戶或金額，入帳仍需逐筆確認。'),
            value: _reminderEnabled,
            onChanged: _reminderBusy || !widget.engine.isUnlocked
                ? null
                : _setReminder,
          ),
          if (_reminderMessage != null) Text(_reminderMessage!),
        ],
        if (_message != null)
          Text(_message!, key: const Key('recurring-message')),
        if (_busy) const LinearProgressIndicator(),
        const SizedBox(height: 16),
        Text('待確認', style: Theme.of(context).textTheme.titleLarge),
        const Text('預設查最近一年；若離線更久，請把起日調早。'),
        TextField(
          key: const Key('recurring-after'),
          controller: _after,
          enabled: enabled,
          decoration: const InputDecoration(labelText: '查詢起日（不含，YYYY-MM-DD）'),
        ),
        TextButton(
          onPressed: enabled ? _load : null,
          child: const Text('重新查詢'),
        ),
        if (_due.isEmpty) const Text('目前查詢範圍沒有待確認項目。'),
        for (final candidate in _due) ...[
          const Divider(),
          Text('${candidate.dueDate} · ${candidate.template.label}'),
          MoneyView(
            money: candidate.template.amount,
            privacy: widget.privacy,
            kind: MoneyKind.transaction,
          ),
          TextButton(
            onPressed: enabled ? () => _confirm(candidate) : null,
            child: const Text('確認入帳'),
          ),
        ],
        const Divider(),
        Text('已設定模板', style: Theme.of(context).textTheme.titleLarge),
        for (final template in _templates) ...[
          Text(
            '${template.label} · ${template.unit.name}／每 ${template.every} 期',
          ),
          MoneyView(
            money: template.amount,
            privacy: widget.privacy,
            kind: MoneyKind.transaction,
          ),
          Row(
            children: [
              TextButton(
                onPressed: enabled ? () => _edit(template) : null,
                child: const Text('修改'),
              ),
              TextButton(
                onPressed: enabled ? () => _remove(template) : null,
                child: const Text('停用'),
              ),
            ],
          ),
        ],
        const Divider(),
        Text(
          _editing == null ? '新增模板' : '修改模板',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        if (widget.privacy == PrivacyMode.hidden)
          const Text('先顯示金額，才能設定或確認定期交易。')
        else ...[
          TextField(
            key: const Key('recurring-label'),
            controller: _label,
            enabled: enabled,
            decoration: const InputDecoration(labelText: '名稱'),
          ),
          DropdownButtonFormField<String>(
            key: ValueKey('recurring-account-$_account'),
            initialValue:
                accounts.any((row) => row.account.id.value == _account)
                ? _account
                : null,
            decoration: const InputDecoration(labelText: '帳戶'),
            items: [
              for (final row in accounts)
                DropdownMenuItem(
                  value: row.account.id.value,
                  child: Text(row.account.name),
                ),
            ],
            onChanged: enabled
                ? (value) => setState(() => _account = value)
                : null,
          ),
          DropdownButtonFormField<bool>(
            key: ValueKey('recurring-kind-$_expense'),
            initialValue: _expense,
            decoration: const InputDecoration(labelText: '類型'),
            items: const [
              DropdownMenuItem(value: true, child: Text('支出')),
              DropdownMenuItem(value: false, child: Text('收入')),
            ],
            onChanged: enabled
                ? (value) => setState(() => _expense = value!)
                : null,
          ),
          TextField(
            key: const Key('recurring-amount'),
            controller: _amount,
            enabled: enabled,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: '每期金額'),
          ),
          TextField(
            key: const Key('recurring-first-date'),
            controller: _firstDate,
            enabled: enabled,
            decoration: const InputDecoration(labelText: '首期日期（YYYY-MM-DD）'),
          ),
          DropdownButtonFormField<RecurrenceUnit>(
            key: ValueKey('recurring-unit-${_unit.name}'),
            initialValue: _unit,
            decoration: const InputDecoration(labelText: '週期'),
            items: const [
              DropdownMenuItem(value: RecurrenceUnit.day, child: Text('日')),
              DropdownMenuItem(value: RecurrenceUnit.week, child: Text('週')),
              DropdownMenuItem(value: RecurrenceUnit.month, child: Text('月')),
              DropdownMenuItem(value: RecurrenceUnit.year, child: Text('年')),
            ],
            onChanged: enabled
                ? (value) => setState(() => _unit = value!)
                : null,
          ),
          TextField(
            key: const Key('recurring-every'),
            controller: _every,
            enabled: enabled,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '每幾期一次'),
          ),
          FilledButton(
            onPressed: enabled ? _save : null,
            child: Text(_editing == null ? '建立模板' : '保存修改'),
          ),
          if (_editing != null)
            TextButton(
              onPressed: enabled ? () => setState(_resetForm) : null,
              child: const Text('取消修改'),
            ),
        ],
      ],
    );
  }
}
