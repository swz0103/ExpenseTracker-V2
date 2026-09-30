part of 'main.dart';

class _CardInstallmentScreen extends StatefulWidget {
  const _CardInstallmentScreen({
    required this.engine,
    required this.accounts,
    required this.privacy,
    required this.onActivity,
  });

  final PreviewEngine engine;
  final List<AccountSummary> accounts;
  final PrivacyMode privacy;
  final Future<void> Function(PublicId eventId) onActivity;

  @override
  State<_CardInstallmentScreen> createState() => _CardInstallmentScreenState();
}

class _CardInstallmentScreenState extends State<_CardInstallmentScreen> {
  final _count = TextEditingController(text: '3');
  final _includedFee = TextEditingController(text: '0');
  final _firstClose = TextEditingController();
  List<CreditCardTerms> _terms = const [];
  List<CardInstallmentPurchase> _available = const [];
  List<CardInstallmentFact> _saved = const [];
  PublicId? _cardId, _purchaseId;
  CardInstallmentSchedule? _review;
  String? _message;
  bool _busy = false, _pending = false;
  int _request = 0;

  List<AccountSummary> get _cards => widget.accounts
      .where((row) => row.account.kind == AccountKind.creditCard)
      .toList();

  CreditCardTerms? get _selectedTerms =>
      _terms.where((row) => row.cardId == _cardId).firstOrNull;

  CardInstallmentPurchase? get _selectedPurchase =>
      _available.where((row) => row.purchaseEventId == _purchaseId).firstOrNull;

  @override
  void initState() {
    super.initState();
    _cardId = _cards.firstOrNull?.account.id;
    unawaited(_load());
  }

  @override
  void dispose() {
    _request++;
    _count.dispose();
    _includedFee.dispose();
    _firstClose.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final request = ++_request;
    final cardId = _cardId;
    if (cardId == null || !widget.engine.isUnlocked) return;
    try {
      final terms = await widget.engine.savedCreditCards();
      final available = await widget.engine.availableInstallmentPurchases(
        cardId,
      );
      final saved = await widget.engine.savedCardInstallmentPlans(cardId);
      final pending = await widget.engine.hasPendingInstallmentPlan();
      if (!mounted || request != _request || !widget.engine.isUnlocked) return;
      setState(() {
        _terms = terms;
        _available = available;
        _saved = saved;
        _pending = pending;
        if (!available.any((row) => row.purchaseEventId == _purchaseId)) {
          _purchaseId = null;
          _review = null;
        }
      });
    } catch (_) {
      if (mounted && request == _request && widget.engine.isUnlocked) {
        setState(() => _message = '無法核對已入帳刷卡資料，請檢查帳本狀態。');
      }
    }
  }

  void _prepare() {
    if (_busy ||
        !widget.engine.isUnlocked ||
        widget.privacy == PrivacyMode.hidden ||
        _pending) {
      return;
    }
    try {
      final purchase = _selectedPurchase;
      final terms = _selectedTerms;
      if (purchase == null || terms == null) throw const FormatException();
      final count = int.parse(_count.text.trim());
      final fee = Money.parse(terms.currency, _includedFee.text.trim());
      final principal = purchase.amount - fee;
      final plan = CardInstallmentSchedule(
        purchaseEventId: purchase.purchaseEventId,
        workspace: widget.engine.workspace,
        cardId: terms.cardId,
        principal: principal,
        fixedFee: fee,
        firstScheduledClose: BusinessDate.parse(_firstClose.text.trim()),
        closingDay: terms.closingDay,
        count: count,
      );
      if (plan.firstScheduledClose.compareTo(purchase.postedOn) < 0) {
        throw const FormatException();
      }
      setState(() {
        _review = plan;
        _message = null;
      });
    } catch (_) {
      setState(() {
        _review = null;
        _message = '請檢查期數、首期結帳日，以及已含在原刷卡額內的費用。';
      });
    }
  }

  Future<void> _save() async {
    final plan = _review;
    if (plan == null ||
        _busy ||
        !widget.engine.isUnlocked ||
        widget.privacy == PrivacyMode.hidden) {
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await widget.engine.submitCardInstallmentPlan(plan);
      if (mounted && widget.engine.isUnlocked) {
        setState(() {
          _review = null;
          _purchaseId = null;
          _message = '已保存分期預估。實際帳單仍以發卡行確認資料為準。';
        });
        await _load();
      }
    } catch (_) {
      if (mounted && widget.engine.isUnlocked) {
        setState(() => _message = '保存結果未確認；請先核對或重試同一筆，勿另建計畫。');
        await _load();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _retry() async {
    if (_busy ||
        !widget.engine.isUnlocked ||
        widget.privacy == PrivacyMode.hidden) {
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.engine.retryPendingInstallmentPlan();
      if (mounted && widget.engine.isUnlocked) {
        setState(() => _message = '已核對並保存原分期計畫。');
        await _load();
      }
    } catch (_) {
      if (mounted && widget.engine.isUnlocked) {
        setState(() => _message = '原計畫仍待核對，請保留資料並稍後重試。');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.engine.isUnlocked) return const SizedBox.shrink();
    if (widget.privacy == PrivacyMode.hidden) {
      return const Text('目前已隱藏金額；顯示金額後可檢視分期。');
    }
    final review = _review;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('信用卡分期', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        const Text('只為已入帳刷卡建立還款預估；不會再次記支出，也不代表發卡行已確認帳單。'),
        const SizedBox(height: 12),
        if (_cards.isEmpty)
          const Text('請先建立信用卡帳戶。')
        else ...[
          DropdownButtonFormField<PublicId>(
            key: const ValueKey('installment-card'),
            initialValue: _cardId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: '信用卡'),
            items: [
              for (final row in _cards)
                DropdownMenuItem(
                  value: row.account.id,
                  child: Text(row.account.name),
                ),
            ],
            onChanged: _busy
                ? null
                : (value) {
                    setState(() {
                      _cardId = value;
                      _purchaseId = null;
                      _review = null;
                      _available = const [];
                      _saved = const [];
                    });
                    unawaited(_load());
                  },
          ),
          const SizedBox(height: 12),
          if (_pending) ...[
            const Text('前一筆分期保存仍待核對，請先重試同一筆。'),
            TextButton(
              key: const ValueKey('retry-installment'),
              onPressed: _busy ? null : _retry,
              child: const Text('核對並重試'),
            ),
          ],
          if (_available.isEmpty) const Text('目前沒有可建立分期的已入帳刷卡。'),
          if (_available.isNotEmpty) ...[
            DropdownButtonFormField<PublicId>(
              key: const ValueKey('installment-purchase'),
              initialValue: _purchaseId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: '已入帳刷卡（最近 100 筆）'),
              items: [
                for (final row in _available)
                  DropdownMenuItem(
                    value: row.purchaseEventId,
                    child: Text(
                      '${row.postedOn} · ${row.amount.majorText} ${row.amount.currency.code}',
                    ),
                  ),
              ],
              onChanged: _busy || _pending
                  ? null
                  : (value) => setState(() {
                      _purchaseId = value;
                      _review = null;
                    }),
            ),
            const SizedBox(height: 8),
            for (final (key, label, controller) in [
              ('installment-count', '期數（2–120）', _count),
              ('installment-fee', '原刷卡額內含固定費用（可填 0）', _includedFee),
              ('installment-first-close', '首期預計結帳日 YYYY-MM-DD', _firstClose),
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextField(
                  key: ValueKey(key),
                  controller: controller,
                  enabled: !_busy && !_pending,
                  onChanged: (_) => setState(() => _review = null),
                  decoration: InputDecoration(labelText: label),
                ),
              ),
            FilledButton(
              key: const ValueKey('review-installment'),
              onPressed: _busy || _pending ? null : _prepare,
              child: const Text('檢視分期預估'),
            ),
          ],
          if (review != null) ...[
            const SizedBox(height: 12),
            Text(
              '原刷卡額 ${(review.principal + review.fixedFee).majorText} ${review.principal.currency.code}；下列只是預估，不會增加帳本支出。',
            ),
            for (final item in review.installments)
              ListTile(
                title: Text('第 ${item.number} 期 · ${item.scheduledClose}'),
                subtitle: Text(
                  '本金 ${item.principal.majorText}；費用 ${item.fee.majorText}',
                ),
                trailing: Text(item.projectedCharge.majorText),
              ),
            FilledButton(
              key: const ValueKey('save-installment'),
              onPressed: _busy ? null : _save,
              child: const Text('確認保存預估'),
            ),
          ],
          const SizedBox(height: 16),
          Text('已保存計畫', style: Theme.of(context).textTheme.titleMedium),
          if (_saved.isEmpty) const Text('尚無分期計畫。'),
          for (final fact in _saved) ...[
            ListTile(
              title: Text(
                '${fact.plan.count} 期 · 首期 ${fact.plan.firstScheduledClose}',
              ),
              subtitle: Text('原刷卡 ${fact.plan.purchaseEventId.value}'),
              trailing: Text(
                (fact.plan.principal + fact.plan.fixedFee).majorText,
              ),
            ),
            if (fact.refunds.isNotEmpty)
              ListTile(
                key: ValueKey(
                  'installment-refund-${fact.plan.purchaseEventId}',
                ),
                contentPadding: const EdgeInsets.only(left: 32, right: 16),
                title: Text(
                  '退款後計畫需核對 · 已退 ${fact.refunded.majorText} ${fact.refunded.currency.code}',
                ),
                subtitle: const Text('原分期預估作為歷史保留，不自動重算或冒充發卡行後續帳單。'),
                trailing: TextButton(
                  key: ValueKey(
                    'installment-refund-activity-${fact.plan.purchaseEventId}',
                  ),
                  onPressed: _busy
                      ? null
                      : () => widget.onActivity(fact.plan.purchaseEventId),
                  child: const Text('查看活動'),
                ),
              ),
          ],
        ],
        if (_message != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_message!, key: const ValueKey('installment-message')),
          ),
      ],
    );
  }
}
