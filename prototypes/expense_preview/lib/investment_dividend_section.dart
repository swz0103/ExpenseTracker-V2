part of 'main.dart';

/// Broker-reported cash dividends are reviewed as investment facts, never
/// entered through the ordinary income form.
class _InvestmentDividendSection extends StatefulWidget {
  const _InvestmentDividendSection({
    required this.engine,
    required this.buys,
    required this.accounts,
    required this.privacy,
    required this.otherPending,
    required this.onSaved,
  });

  final PreviewEngine engine;
  final List<InvestmentBuyFact> buys;
  final List<AccountSummary> accounts;
  final PrivacyMode privacy;
  final bool otherPending;
  final Future<void> Function() onSaved;

  @override
  State<_InvestmentDividendSection> createState() =>
      _InvestmentDividendSectionState();
}

class _InvestmentDividendSectionState
    extends State<_InvestmentDividendSection> {
  final _paidOn = TextEditingController();
  final _gross = TextEditingController();
  final _tax = TextEditingController(text: '0');
  final _fee = TextEditingController(text: '0');
  final _net = TextEditingController();
  List<InvestmentDividendFact> _saved = const [];
  PublicId? _buyId;
  InvestmentDividendPreview? _review;
  String? _message;
  bool _pending = false;
  bool _busy = false;
  int _request = 0;

  List<InvestmentBuyFact> get _positions {
    final seen = <String>{};
    return widget.buys
        .where((fact) {
          final buy = fact.preview;
          return seen.add('${buy.account.id}|${buy.instrument.id}');
        })
        .toList(growable: false);
  }

  InvestmentBuyPreview? get _selected => _positions
      .where((fact) => fact.preview.id == _buyId)
      .firstOrNull
      ?.preview;

  Account? get _funding {
    final buy = _selected;
    if (buy == null) return null;
    return widget.accounts
        .where(
          (summary) =>
              summary.account.id == buy.funding.id &&
              summary.account.state == AccountState.active &&
              (summary.account.kind == AccountKind.cash ||
                  summary.account.kind == AccountKind.bank) &&
              summary.account.currency == buy.instrument.tradingCurrency,
        )
        .firstOrNull
        ?.account;
  }

  bool get _canEdit =>
      !_busy &&
      !_pending &&
      !widget.otherPending &&
      widget.engine.isUnlocked &&
      widget.privacy != PrivacyMode.hidden;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _paidOn.text =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant _InvestmentDividendSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.engine, oldWidget.engine)) {
      _request++;
      _saved = const [];
      _buyId = null;
      _review = null;
      _pending = false;
      unawaited(_load());
    } else if (!_positions.any((fact) => fact.preview.id == _buyId)) {
      _buyId = null;
      _review = null;
    }
    if (!widget.engine.isUnlocked || widget.privacy == PrivacyMode.hidden) {
      _request++;
      _review = null;
    }
  }

  @override
  void dispose() {
    _request++;
    for (final controller in [_paidOn, _gross, _tax, _fee, _net]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final request = ++_request;
    if (!widget.engine.isUnlocked || widget.privacy == PrivacyMode.hidden) {
      return;
    }
    try {
      final saved = await widget.engine.investmentDividends();
      final pending = await widget.engine.hasPendingInvestmentDividend();
      if (!mounted ||
          request != _request ||
          !widget.engine.isUnlocked ||
          widget.privacy == PrivacyMode.hidden) {
        return;
      }
      setState(() {
        _saved = saved;
        _pending = pending;
      });
    } catch (_) {
      if (mounted && request == _request) {
        setState(() => _message = '無法核對股息紀錄；請保留資料並稍後重試。');
      }
    }
  }

  void _prepare() {
    if (!_canEdit) return;
    try {
      final buy = _selected;
      final funding = _funding;
      if (buy == null || funding == null) throw const FormatException();
      final date = BusinessDate.parse(_paidOn.text.trim());
      if (date.compareTo(buy.tradedOn) < 0 ||
          date.compareTo(funding.openedOn) < 0) {
        throw const FormatException();
      }
      final currency = buy.instrument.tradingCurrency;
      final workspace = widget.engine.workspace;
      final preview = InvestmentDividendPreview.create(
        id: PublicId.generate(),
        operation: OperationKey(workspace, OperationId(PublicId.generate())),
        paidOn: date,
        broker: buy.broker,
        account: buy.account,
        instrument: buy.instrument,
        funding: FundingCashAccount(
          id: funding.id,
          workspace: workspace,
          currency: funding.currency,
          expectedVersion: funding.version,
        ),
        gross: Money.parse(currency, _gross.text.trim()),
        withholdingTax: Money.parse(currency, _tax.text.trim()),
        fee: Money.parse(currency, _fee.text.trim()),
        reportedNet: Money.parse(currency, _net.text.trim()),
      );
      setState(() {
        _review = preview;
        _message = null;
      });
    } catch (_) {
      setState(() {
        _review = null;
        _message = '請核對日期、幣別及金額；淨入帳須等於股息總額減預扣稅與費用。';
      });
    }
  }

  Future<void> _save() async {
    final preview = _review;
    if (preview == null || !_canEdit) return;
    final request = ++_request;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await widget.engine.submitInvestmentDividend(preview);
      if (!mounted || request != _request) return;
      setState(() {
        _review = null;
        _message = '股息與現金入帳已一起保存。';
      });
      await _load();
      await widget.onSaved();
    } catch (_) {
      if (mounted && request == _request) {
        setState(() {
          _review = null;
          _message = '結果尚未確認；請重試同一筆股息，勿另建新交易。';
        });
        await _load();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _retry() async {
    if (_busy || !_pending || !widget.engine.isUnlocked) return;
    final request = ++_request;
    setState(() => _busy = true);
    try {
      await widget.engine.retryPendingInvestmentDividend();
      if (!mounted || request != _request) return;
      setState(() => _message = '已核對並保存待確認股息。');
      await _load();
      await widget.onSaved();
    } catch (_) {
      if (mounted && request == _request) {
        setState(() => _message = '股息仍待核對；請保留資料並稍後重試。');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resolvePending() async {
    if (_busy ||
        !_pending ||
        !widget.engine.isUnlocked ||
        widget.privacy == PrivacyMode.hidden) {
      return;
    }
    if (!await _confirmInvestmentIntentResolution(context, '股息') || !mounted) {
      return;
    }
    final request = ++_request;
    setState(() => _busy = true);
    try {
      final resolution = await widget.engine.resolvePendingInvestmentDividend();
      if (!mounted ||
          request != _request ||
          !widget.engine.isUnlocked ||
          widget.privacy == PrivacyMode.hidden) {
        return;
      }
      setState(() {
        _review = null;
        _message = resolution == InvestmentIntentResolution.committed
            ? '帳本已有同一筆股息；已完成本機確認，沒有重複入帳。'
            : '帳本確認沒有這筆股息；已安全捨棄待確認意圖。';
      });
      await _load();
      await widget.onSaved();
    } catch (_) {
      if (mounted && request == _request) {
        setState(() => _message = '無法安全判定股息結果；待確認資料已保留，請重試。');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.engine.isUnlocked || widget.privacy == PrivacyMode.hidden) {
      return const SizedBox.shrink();
    }
    final selected = _selected;
    final funding = _funding;
    final review = _review;
    return ExpansionTile(
      key: const ValueKey('investment-dividend-section'),
      title: const Text('現金股息'),
      subtitle: const Text('依券商實際通知登記；不列入日常收入。'),
      children: [
        if (_pending) ...[
          const Text('上一筆股息仍待確認；可重試同一筆，或先核對帳本再安全處理。'),
          Row(
            children: [
              TextButton(
                key: const ValueKey('retry-investment-dividend'),
                onPressed: _busy ? null : _retry,
                child: const Text('核對並重試股息'),
              ),
              TextButton(
                key: const ValueKey('resolve-investment-dividend'),
                onPressed: _busy ? null : _resolvePending,
                child: const Text('核對結果或捨棄'),
              ),
            ],
          ),
        ],
        if (_positions.isEmpty)
          const Text('請先記錄買入，才能選擇投資帳戶與商品。')
        else
          DropdownButtonFormField<PublicId>(
            key: const ValueKey('investment-dividend-position'),
            initialValue: _buyId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: '投資帳戶與商品'),
            items: [
              for (final fact in _positions)
                DropdownMenuItem(
                  value: fact.preview.id,
                  child: Text(
                    '${fact.preview.account.name} · ${fact.preview.instrument.marketCode}:${fact.preview.instrument.symbol}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: _canEdit
                ? (id) => setState(() {
                    _buyId = id;
                    _review = null;
                    _message = null;
                  })
                : null,
          ),
        if (selected != null) ...[
          if (funding == null)
            const Text('連結的現金或銀行帳戶目前不可用，無法登記股息。')
          else
            Text('現金入帳：${funding.name} · ${funding.currency.code}'),
          for (final (key, label, controller) in [
            ('investment-dividend-date', '入帳日期 YYYY-MM-DD', _paidOn),
            ('investment-dividend-gross', '股息總額', _gross),
            ('investment-dividend-tax', '預扣稅（可填 0）', _tax),
            ('investment-dividend-fee', '費用（可填 0）', _fee),
            ('investment-dividend-net', '實際淨入帳', _net),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TextField(
                key: ValueKey(key),
                controller: controller,
                enabled: _canEdit,
                keyboardType: key == 'investment-dividend-date'
                    ? TextInputType.datetime
                    : const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() => _review = null),
                decoration: InputDecoration(labelText: label),
              ),
            ),
          FilledButton(
            key: const ValueKey('review-investment-dividend'),
            onPressed: _canEdit && funding != null ? _prepare : null,
            child: const Text('檢查股息與入帳'),
          ),
          if (review != null) ...[
            Text(
              '${review.paidOn} · ${review.instrument.marketCode}:${review.instrument.symbol}',
            ),
            Text(
              '${review.gross.majorText} − ${review.withholdingTax.majorText} − ${review.fee.majorText} = ${review.netCashCredit.majorText} ${review.netCashCredit.currency.code}',
              key: const ValueKey('investment-dividend-cash-preview'),
            ),
            const Text('確認後會同時保存股息事實與現金入帳。'),
            FilledButton(
              key: const ValueKey('save-investment-dividend'),
              onPressed: _canEdit ? _save : null,
              child: const Text('確認股息並入帳'),
            ),
          ],
        ],
        Text('已記錄股息', style: Theme.of(context).textTheme.titleMedium),
        for (final fact in _saved)
          ListTile(
            key: ValueKey('investment-dividend-${fact.preview.id.value}'),
            title: Text(
              '${fact.preview.paidOn} · ${fact.preview.instrument.marketCode}:${fact.preview.instrument.symbol}',
            ),
            subtitle: Text(
              '總額 ${fact.preview.gross.majorText} · 預扣稅 ${fact.preview.withholdingTax.majorText} · 費用 ${fact.preview.fee.majorText}',
            ),
            trailing: Text(
              '${fact.preview.netCashCredit.majorText} ${fact.preview.netCashCredit.currency.code}',
            ),
          ),
        if (_message != null)
          Text(_message!, key: const ValueKey('investment-dividend-message')),
      ],
    );
  }
}
