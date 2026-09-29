part of 'main.dart';

class _CardSettingsScreen extends StatefulWidget {
  const _CardSettingsScreen({
    required this.engine,
    required this.accounts,
    required this.privacy,
  });

  final PreviewEngine engine;
  final List<AccountSummary> accounts;
  final PrivacyMode privacy;

  @override
  State<_CardSettingsScreen> createState() => _CardSettingsScreenState();
}

class _CardSettingsScreenState extends State<_CardSettingsScreen> {
  final _closingDay = TextEditingController();
  final _dueDay = TextEditingController();
  final _limit = TextEditingController();
  List<CreditCardTerms> _cards = const [];
  PublicId? _cardId;
  CreditCardTerms? _pendingTerms;
  OperationId? _pendingOperation;
  String? _pendingSignature, _message;
  bool _busy = false, _loaded = false;
  int _request = 0;

  CreditCardTerms? get _selected =>
      _cards.where((card) => card.cardId == _cardId).firstOrNull;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _request++;
    _closingDay.dispose();
    _dueDay.dispose();
    _limit.dispose();
    super.dispose();
  }

  void _adopt(CreditCardTerms? terms) {
    _closingDay.text = terms?.closingDay.toString() ?? '';
    _dueDay.text = terms?.dueDay.toString() ?? '';
    _limit.text = terms?.limit?.majorText ?? '';
  }

  Future<bool> _load() async {
    final request = ++_request;
    if (!widget.engine.isUnlocked) return false;
    try {
      final cards = await widget.engine.savedCreditCards();
      if (!mounted || request != _request || !widget.engine.isUnlocked) {
        return false;
      }
      setState(() {
        _cards = cards;
        if (!cards.any((card) => card.cardId == _cardId)) {
          _cardId = cards.firstOrNull?.cardId;
        }
        _adopt(_selected);
        _pendingTerms = null;
        _pendingOperation = null;
        _pendingSignature = null;
        _loaded = true;
      });
      return true;
    } catch (_) {
      if (mounted && request == _request && widget.engine.isUnlocked) {
        setState(() => _message = '無法讀取卡片設定；請確認帳本資料健康後重試。');
      }
      return false;
    }
  }

  Future<void> _save() async {
    if (_busy ||
        !widget.engine.isUnlocked ||
        widget.privacy == PrivacyMode.hidden) {
      return;
    }
    final current = _selected;
    if (current == null) return;
    final closing = int.tryParse(_closingDay.text.trim());
    final due = int.tryParse(_dueDay.text.trim());
    if (closing == null ||
        closing < 1 ||
        closing > 31 ||
        due == null ||
        due < 1 ||
        due > 31) {
      setState(() => _message = '結帳日與繳款日請輸入 1–31 的整數。');
      return;
    }
    Money? limit;
    final limitInput = _limit.text.trim();
    if (limitInput.isNotEmpty) {
      try {
        limit = Money.parse(current.currency, limitInput);
        if (limit.minorUnits <= BigInt.zero) throw const FormatException();
      } catch (_) {
        setState(() => _message = '額度請輸入大於零的金額，或留空。');
        return;
      }
    }
    if (closing == current.closingDay &&
        due == current.dueDay &&
        limit == current.limit) {
      setState(() => _message = '設定沒有變更。');
      return;
    }
    final signature =
        '${current.cardId}|${current.version}|$closing|$due|${limit?.minorUnits}';
    if (signature != _pendingSignature) {
      _pendingTerms = CreditCardTerms(
        workspace: current.workspace,
        cardId: current.cardId,
        currency: current.currency,
        closingDay: closing,
        dueDay: due,
        limit: limit,
        version: current.version + 1,
      );
      _pendingOperation = OperationId(PublicId.generate());
      _pendingSignature = signature;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await widget.engine.reviseCreditCard(_pendingTerms!, _pendingOperation!);
      final loaded = await _load();
      if (loaded && mounted) {
        setState(() => _message = '已更新卡片設定。');
      }
    } catch (_) {
      if (mounted && widget.engine.isUnlocked) {
        setState(() => _message = '無法確認是否已儲存；請保持欄位不變並重試同一筆，或返回後重新讀取。');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.engine.isUnlocked) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('信用卡設定', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        const Text('結帳日與繳款日是預定規則；修改設定不會更改發卡行已確認帳單。'),
        const SizedBox(height: 12),
        if (widget.privacy == PrivacyMode.hidden)
          const Text('目前已隱藏資料。點右上角「顯示金額」後可檢視及修改卡片設定。')
        else if (!_loaded)
          const CircularProgressIndicator()
        else if (_cards.isEmpty)
          const Text('目前沒有可修改的信用卡設定。')
        else ...[
          DropdownButtonFormField<PublicId>(
            key: const ValueKey('settings-card'),
            initialValue: _cardId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: '信用卡'),
            items: [
              for (final card in _cards)
                DropdownMenuItem(
                  value: card.cardId,
                  child: Text(
                    '${widget.accounts.where((row) => row.account.id == card.cardId).firstOrNull?.account.name ?? '信用卡'} · ${card.currency.code}',
                  ),
                ),
            ],
            onChanged: _busy
                ? null
                : (value) => setState(() {
                    _cardId = value;
                    _adopt(_selected);
                    _pendingTerms = null;
                    _pendingOperation = null;
                    _pendingSignature = null;
                    _message = null;
                  }),
          ),
          const SizedBox(height: 8),
          Text(
            '目前版本：${_selected?.version ?? '—'}',
            key: const ValueKey('settings-version'),
          ),
          const SizedBox(height: 12),
          for (final (key, label, controller) in [
            ('settings-closing-day', '預定結帳日（1–31）', _closingDay),
            ('settings-due-day', '預定繳款日（1–31）', _dueDay),
            ('settings-limit', '額度（可留空）', _limit),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TextField(
                key: ValueKey(key),
                controller: controller,
                enabled: !_busy,
                keyboardType: key == 'settings-limit'
                    ? const TextInputType.numberWithOptions(decimal: true)
                    : TextInputType.number,
                decoration: InputDecoration(labelText: label),
              ),
            ),
          FilledButton(
            key: const ValueKey('save-card-settings'),
            onPressed: _busy ? null : _save,
            child: const Text('儲存卡片設定'),
          ),
        ],
        if (_message != null)
          Text(_message!, key: const ValueKey('settings-status')),
      ],
    );
  }
}
