part of 'main.dart';

/// Issuer authorizations are estimates. Only a separately confirmed posting
/// changes the Ledger balance and reporting period.
class _CardAuthorizationScreen extends StatefulWidget {
  const _CardAuthorizationScreen({
    required this.engine,
    required this.accounts,
    required this.activeCardIds,
    required this.privacy,
    required this.onChanged,
  });

  final PreviewEngine engine;
  final List<AccountSummary> accounts;
  final Set<PublicId> activeCardIds;
  final PrivacyMode privacy;
  final Future<void> Function() onChanged;

  @override
  State<_CardAuthorizationScreen> createState() =>
      _CardAuthorizationScreenState();
}

class _CardAuthorizationScreenState extends State<_CardAuthorizationScreen> {
  final _authorizedOn = TextEditingController();
  final _authorizedAmount = TextEditingController();
  final _postedOn = TextEditingController();
  final _settledAmount = TextEditingController();
  List<CardAuthorizationFact> _facts = const [];
  PublicId? _cardId, _chargeId;
  String? _message;
  bool _busy = false;
  bool _loaded = false;
  bool _pendingAuthorization = false;
  bool _pendingCancellation = false;
  bool _pendingPosting = false;
  bool _newSeparateAuthorization = false;
  int _request = 0;

  List<AccountSummary> get _cards => widget.accounts
      .where((row) => row.account.kind == AccountKind.creditCard)
      .toList();

  bool get _selectedCardActive =>
      _cardId != null && widget.activeCardIds.contains(_cardId);

  List<CardAuthorizationFact> get _pending => _facts
      .where(
        (fact) =>
            fact.charge.cardId == _cardId &&
            fact.state == CardAuthorizationState.pending,
      )
      .toList();

  Currency? get _currency => _cards
      .where((row) => row.account.id == _cardId)
      .firstOrNull
      ?.account
      .currency;

  @override
  void initState() {
    super.initState();
    _cardId = _cards.firstOrNull?.account.id;
    unawaited(_load());
  }

  @override
  void dispose() {
    _request++;
    _authorizedOn.dispose();
    _authorizedAmount.dispose();
    _postedOn.dispose();
    _settledAmount.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final request = ++_request;
    if (!widget.engine.isUnlocked) return;
    try {
      final facts = await widget.engine.savedCardAuthorizations();
      final intents = await widget.engine.pendingCardAuthorizationIntents();
      if (!mounted || request != _request || !widget.engine.isUnlocked) return;
      setState(() {
        _loaded = true;
        _facts = facts;
        _pendingAuthorization = intents.authorization;
        _pendingCancellation = intents.cancellation;
        _pendingPosting = intents.posting;
        if (!_pending.any((fact) => fact.charge.id == _chargeId)) {
          _chargeId = _pending.firstOrNull?.charge.id;
        }
      });
    } catch (_) {
      if (mounted && request == _request && widget.engine.isUnlocked) {
        setState(() {
          _loaded = false;
          _message = '無法讀取卡片待入帳資料；請保留現有帳本並稍後重試。';
        });
      }
    }
  }

  Future<void> _run(
    Future<void> Function() action, {
    bool refreshAccounts = false,
  }) async {
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
      await action();
      if (mounted && widget.engine.isUnlocked) {
        await _load();
        if (refreshAccounts) await widget.onChanged();
      }
    } catch (_) {
      if (mounted && widget.engine.isUnlocked) {
        setState(() => _message = '操作結果尚未確認；請先重試前次操作，不要重新建立交易。');
        await _load();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _authorize() => _run(() async {
    final cardId = _cardId;
    final currency = _currency;
    if (cardId == null || currency == null) throw const FormatException();
    await widget.engine.submitCardAuthorization(
      cardId: cardId,
      authorizedOn: BusinessDate.parse(_authorizedOn.text.trim()),
      authorizedAmount: Money.parse(currency, _authorizedAmount.text.trim()),
      startNew: _newSeparateAuthorization,
    );
    if (mounted) {
      _authorizedOn.clear();
      _authorizedAmount.clear();
      _newSeparateAuthorization = false;
      setState(() => _message = '已記錄待入帳；尚未影響餘額或帳單。');
    }
  });

  Future<void> _cancel() => _run(() async {
    final chargeId = _chargeId;
    if (chargeId == null) throw const FormatException();
    await widget.engine.submitCardAuthorizationCancellation(chargeId);
    if (mounted) setState(() => _message = '已取消待入帳紀錄。');
  });

  Future<void> _post() => _run(() async {
    final chargeId = _chargeId;
    final currency = _currency;
    if (chargeId == null || currency == null) throw const FormatException();
    await widget.engine.submitAuthorizedCardPurchase(
      chargeId: chargeId,
      postedOn: BusinessDate.parse(_postedOn.text.trim()),
      settledAmount: Money.parse(currency, _settledAmount.text.trim()),
    );
    if (mounted) {
      _postedOn.clear();
      _settledAmount.clear();
      setState(() => _message = '已正式入帳；卡片負債與支出已更新。');
    }
  }, refreshAccounts: true);

  Future<void> _retry(String kind) => _run(() async {
    await widget.engine.retryPendingCardAuthorizationIntent(kind);
    if (mounted) setState(() => _message = '已核對前次操作。');
  }, refreshAccounts: kind == 'posting');

  @override
  Widget build(BuildContext context) {
    if (!widget.engine.isUnlocked) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('信用卡待入帳', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        const Text('授權金額只是估計；發卡行正式入帳後才更新卡片負債與支出。'),
        const SizedBox(height: 12),
        if (!_loaded && _message == null) const LinearProgressIndicator(),
        if (widget.privacy == PrivacyMode.hidden)
          const Text('目前已隱藏金額。點按上方「顯示金額」才能檢視或操作待入帳。')
        else if (_cards.isEmpty)
          const Text('請先建立信用卡帳戶。')
        else ...[
          DropdownButtonFormField<PublicId>(
            key: const ValueKey('authorization-card'),
            initialValue: _cardId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: '信用卡'),
            items: [
              for (final row in _cards)
                DropdownMenuItem(
                  value: row.account.id,
                  child: Text(
                    '${row.account.name} · ${row.account.currency.code}'
                    '${widget.activeCardIds.contains(row.account.id) ? '' : ' · 已停用'}',
                  ),
                ),
            ],
            onChanged: _busy
                ? null
                : (value) => setState(() {
                    _cardId = value;
                    _chargeId = null;
                    _chargeId = _pending.firstOrNull?.charge.id;
                  }),
          ),
          const SizedBox(height: 8),
          if (!_selectedCardActive)
            const Text('此卡已停用，不可新增授權；停用前的待入帳仍可取消或依發卡行結果正式入帳。'),
          TextField(
            key: const ValueKey('authorization-date'),
            controller: _authorizedOn,
            enabled: !_busy && _selectedCardActive,
            decoration: const InputDecoration(labelText: '授權日期（YYYY-MM-DD）'),
          ),
          TextField(
            key: const ValueKey('authorization-amount'),
            controller: _authorizedAmount,
            enabled: !_busy && _selectedCardActive,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: '授權估計金額'),
          ),
          CheckboxListTile(
            key: const ValueKey('authorization-new-separate'),
            value: _newSeparateAuthorization,
            onChanged: _busy || !_selectedCardActive
                ? null
                : (value) => setState(
                    () => _newSeparateAuthorization = value ?? false,
                  ),
            title: const Text('這是另一筆相同授權'),
          ),
          FilledButton(
            key: const ValueKey('create-authorization'),
            onPressed: _busy || !_loaded || !_selectedCardActive
                ? null
                : _authorize,
            child: const Text('記錄待入帳'),
          ),
          const SizedBox(height: 16),
          if (_pending.isEmpty)
            const Text('目前沒有待入帳紀錄。')
          else ...[
            DropdownButtonFormField<PublicId>(
              key: ValueKey('authorization-pending-${_chargeId?.value}'),
              initialValue: _chargeId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: '待入帳紀錄'),
              items: [
                for (final fact in _pending)
                  DropdownMenuItem(
                    value: fact.charge.id,
                    child: Text(
                      '${fact.charge.authorizedOn} · '
                      '${fact.charge.authorizedAmount.majorText} '
                      '${fact.charge.authorizedAmount.currency.code}',
                    ),
                  ),
              ],
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _chargeId = value),
            ),
            TextField(
              key: const ValueKey('authorization-posted-date'),
              controller: _postedOn,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: '發卡行入帳日期（YYYY-MM-DD）',
              ),
            ),
            TextField(
              key: const ValueKey('authorization-settled-amount'),
              controller: _settledAmount,
              enabled: !_busy,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: '實際入帳金額'),
            ),
            Row(
              children: [
                TextButton(
                  key: const ValueKey('cancel-authorization'),
                  onPressed: _busy || !_loaded ? null : _cancel,
                  child: const Text('取消授權'),
                ),
                FilledButton(
                  key: const ValueKey('post-authorization'),
                  onPressed: _busy || !_loaded ? null : _post,
                  child: const Text('確認正式入帳'),
                ),
              ],
            ),
          ],
          if (_pendingAuthorization || _pendingCancellation || _pendingPosting)
            const Text('前次操作結果待核對；請先重試，不要輸入另一筆。'),
          if (_facts.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('最近授權狀態'),
            for (final fact in _facts.reversed.take(10))
              Text(
                '${fact.charge.authorizedOn} · '
                '${fact.charge.authorizedAmount.majorText} '
                '${fact.charge.authorizedAmount.currency.code} · '
                '${switch (fact.state) {
                  CardAuthorizationState.pending => '待入帳',
                  CardAuthorizationState.cancelled => '已取消',
                  CardAuthorizationState.posted => '已正式入帳',
                }}',
              ),
          ],
          for (final (kind, waiting, label) in [
            ('authorization', _pendingAuthorization, '重試前次授權'),
            ('cancellation', _pendingCancellation, '重試前次取消'),
            ('posting', _pendingPosting, '重試前次入帳'),
          ])
            if (waiting)
              TextButton(
                key: ValueKey('retry-$kind'),
                onPressed: _busy || !_loaded ? null : () => _retry(kind),
                child: Text(label),
              ),
        ],
        if (_message != null)
          Text(_message!, key: const ValueKey('authorization-status')),
      ],
    );
  }
}
