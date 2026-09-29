part of 'main.dart';

class _CardStatementScreen extends StatefulWidget {
  const _CardStatementScreen({
    required this.engine,
    required this.accounts,
    required this.privacy,
  });

  final PreviewEngine engine;
  final List<AccountSummary> accounts;
  final PrivacyMode privacy;

  @override
  State<_CardStatementScreen> createState() => _CardStatementScreenState();
}

class _CardStatementScreenState extends State<_CardStatementScreen> {
  final _startsAfter = TextEditingController();
  final _closesOn = TextEditingController();
  final _dueOn = TextEditingController();
  final _billed = TextEditingController();
  final _allocation = TextEditingController();
  List<ConfirmedCardStatement> _statements = const [];
  List<CardUnallocatedPayment> _payments = const [];
  String? _cardId, _statementId, _paymentId, _message;
  String? _pendingStatementSignature, _pendingAllocationSignature;
  PublicId? _pendingStatementId;
  OperationId? _pendingStatementOperation, _pendingAllocationOperation;
  bool _busy = false;
  int _request = 0;

  List<AccountSummary> get _cards => widget.accounts
      .where((row) => row.account.kind == AccountKind.creditCard)
      .toList();

  @override
  void initState() {
    super.initState();
    _cardId = _cards.firstOrNull?.account.id.value;
    unawaited(_load());
  }

  @override
  void dispose() {
    _request++;
    _startsAfter.dispose();
    _closesOn.dispose();
    _dueOn.dispose();
    _billed.dispose();
    _allocation.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final request = ++_request;
    final cardId = _cardId;
    if (cardId == null || !widget.engine.isUnlocked) return;
    try {
      final statements = await widget.engine.confirmedCardStatements(
        PublicId.parse(cardId),
      );
      final payments = await widget.engine.unallocatedCardPayments(
        PublicId.parse(cardId),
      );
      if (!mounted || request != _request || !widget.engine.isUnlocked) return;
      setState(() {
        _statements = statements;
        _payments = payments;
        if (!statements.any(
          (row) =>
              row.id.value == _statementId &&
              row.remainingDue.minorUnits > BigInt.zero,
        )) {
          _statementId = null;
        }
        if (!payments.any(
          (row) =>
              row.eventId.value == _paymentId &&
              row.unallocated.minorUnits > BigInt.zero,
        )) {
          _paymentId = null;
        }
      });
    } catch (_) {
      if (mounted && request == _request && widget.engine.isUnlocked) {
        setState(() => _message = '無法讀取帳單；請先確認帳本資料健康。');
      }
    }
  }

  Future<void> _run(Future<void> Function() work, String error) async {
    if (_busy ||
        !widget.engine.isUnlocked ||
        widget.privacy == PrivacyMode.hidden) {
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await work();
      if (mounted && widget.engine.isUnlocked) await _load();
    } catch (_) {
      if (mounted && widget.engine.isUnlocked) {
        setState(() => _message = error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() => _run(() async {
    final cardId = PublicId.parse(_cardId!);
    final cycle = CardCycle(
      startsAfter: BusinessDate.parse(_startsAfter.text.trim()),
      closesOn: BusinessDate.parse(_closesOn.text.trim()),
      dueOn: BusinessDate.parse(_dueOn.text.trim()),
    );
    final card = _cards.singleWhere((row) => row.account.id == cardId);
    final billed = Money.parse(card.account.currency, _billed.text.trim());
    final signature =
        '$cardId|${cycle.startsAfter}|${cycle.closesOn}|${cycle.dueOn}|${billed.minorUnits}';
    if (signature != _pendingStatementSignature) {
      _pendingStatementSignature = signature;
      _pendingStatementId = PublicId.generate();
      _pendingStatementOperation = OperationId(PublicId.generate());
    }
    await widget.engine.confirmCardStatement(
      statementId: _pendingStatementId!,
      cardId: cardId,
      revision: 1,
      cycle: cycle,
      billed: billed,
      operation: _pendingStatementOperation!,
    );
    if (mounted) {
      _startsAfter.clear();
      _closesOn.clear();
      _dueOn.clear();
      _billed.clear();
      _pendingStatementSignature = null;
      _pendingStatementId = null;
      _pendingStatementOperation = null;
      setState(() => _message = '已保存實際帳單。');
    }
  }, '帳單未保存；請檢查實際日期、重疊帳期與卡片設定後重試。');

  Future<void> _allocate() => _run(() async {
    final statement = _statements
        .where((row) => row.id.value == _statementId)
        .single;
    final payment = _payments
        .where((row) => row.eventId.value == _paymentId)
        .single;
    final amount = Money.parse(
      statement.remainingDue.currency,
      _allocation.text.trim(),
    );
    if (amount.minorUnits <= BigInt.zero ||
        amount.minorUnits > statement.remainingDue.minorUnits ||
        amount.minorUnits > payment.unallocated.minorUnits) {
      throw const FormatException('Allocation exceeds available amount');
    }
    final signature =
        '${payment.eventId}|${statement.id}|${statement.revision}|${amount.minorUnits}';
    if (signature != _pendingAllocationSignature) {
      _pendingAllocationSignature = signature;
      _pendingAllocationOperation = OperationId(PublicId.generate());
    }
    await widget.engine.allocateCardPayment(
      paymentEventId: payment.eventId,
      statementId: statement.id,
      statementRevision: statement.revision,
      amount: amount,
      operation: _pendingAllocationOperation!,
    );
    if (mounted) {
      _allocation.clear();
      _pendingAllocationSignature = null;
      _pendingAllocationOperation = null;
      setState(() => _message = '已將繳款分配至帳單。');
    }
  }, '分配未保存；請檢查帳單未繳額及繳款未分配額後重試。');

  @override
  Widget build(BuildContext context) {
    final cards = _cards;
    if (cards.isEmpty) return const Text('請先建立信用卡帳戶。');
    final payable = _statements
        .where((row) => row.remainingDue.minorUnits > BigInt.zero)
        .toList();
    final available = _payments
        .where((row) => row.unallocated.minorUnits > BigInt.zero)
        .toList();
    final selectedStatement = payable
        .where((row) => row.id.value == _statementId)
        .firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('信用卡帳單', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        const Text('依發卡行提供的實際帳期與繳款日確認；預定結帳日不等於正式帳單。既有繳款需自行指定帳單。'),
        DropdownButtonFormField<String>(
          key: const ValueKey('statement-card'),
          isExpanded: true,
          initialValue: _cardId,
          decoration: const InputDecoration(labelText: '信用卡'),
          items: [
            for (final row in cards)
              DropdownMenuItem(
                value: row.account.id.value,
                child: Text(row.account.name),
              ),
          ],
          onChanged: _busy
              ? null
              : (value) {
                  setState(() {
                    _cardId = value;
                    _statementId = null;
                    _paymentId = null;
                    _statements = const [];
                    _payments = const [];
                    _message = null;
                  });
                  unawaited(_load());
                },
        ),
        const SizedBox(height: 12),
        for (final (key, label, controller) in [
          ('statement-start', '帳期起日之後 YYYY-MM-DD', _startsAfter),
          ('statement-close', '實際結帳日 YYYY-MM-DD', _closesOn),
          ('statement-due', '實際繳款日 YYYY-MM-DD', _dueOn),
          ('statement-billed', '發卡行帳單總額', _billed),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: TextField(
              key: ValueKey(key),
              controller: controller,
              decoration: InputDecoration(labelText: label),
            ),
          ),
        FilledButton(
          key: const ValueKey('confirm-statement'),
          onPressed: _busy || widget.privacy == PrivacyMode.hidden
              ? null
              : _confirm,
          child: const Text('確認並保存帳單'),
        ),
        const SizedBox(height: 16),
        for (final row in _statements)
          ListTile(
            title: Text('結帳 ${row.cycle.closesOn} · 繳款 ${row.cycle.dueOn}'),
            subtitle: Text(
              '發卡行帳單 ${presentMoney(row.billed, widget.privacy, MoneyKind.balance).text} · 已分配 ${presentMoney(row.paid, widget.privacy, MoneyKind.balance).text} · 未繳 ${presentMoney(row.remainingDue, widget.privacy, MoneyKind.balance).text}'
              '${row.billed != row.localCharges ? ' · 本機刷卡合計 ${presentMoney(row.localCharges, widget.privacy, MoneyKind.balance).text}，金額不符請核對' : ''}',
            ),
          ),
        const SizedBox(height: 8),
        Text('繳款歸屬', style: Theme.of(context).textTheme.titleMedium),
        const Text('帳戶層繳款不會自動算入任何帳單；可將未分配金額的一部分指定給已確認帳單。'),
        if (payable.isNotEmpty && available.isNotEmpty) ...[
          DropdownButtonFormField<String>(
            key: const ValueKey('allocation-statement'),
            isExpanded: true,
            initialValue: _statementId,
            decoration: const InputDecoration(labelText: '未繳帳單'),
            items: [
              for (final row in payable)
                DropdownMenuItem(
                  value: row.id.value,
                  child: Text(
                    '${row.cycle.closesOn} · ${presentMoney(row.remainingDue, widget.privacy, MoneyKind.balance).text}',
                  ),
                ),
            ],
            onChanged: _busy
                ? null
                : (value) => setState(() => _statementId = value),
          ),
          DropdownButtonFormField<String>(
            key: const ValueKey('allocation-payment'),
            isExpanded: true,
            initialValue: _paymentId,
            decoration: const InputDecoration(labelText: '未分配繳款'),
            items: [
              for (final row in available)
                DropdownMenuItem(
                  value: row.eventId.value,
                  child: Text(
                    '${row.postedOn} · ${presentMoney(row.unallocated, widget.privacy, MoneyKind.balance).text}',
                  ),
                ),
            ],
            onChanged: _busy
                ? null
                : (value) => setState(() => _paymentId = value),
          ),
          TextField(
            key: const ValueKey('allocation-amount'),
            controller: _allocation,
            decoration: const InputDecoration(labelText: '本次分配金額'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          FilledButton(
            key: const ValueKey('allocate-payment'),
            onPressed:
                _busy ||
                    widget.privacy == PrivacyMode.hidden ||
                    selectedStatement == null ||
                    _paymentId == null
                ? null
                : _allocate,
            child: const Text('確認繳款歸屬'),
          ),
        ] else
          const Text('目前沒有可分配的繳款或未繳帳單。'),
        if (_message != null)
          Text(_message!, key: const ValueKey('statement-status')),
      ],
    );
  }
}
