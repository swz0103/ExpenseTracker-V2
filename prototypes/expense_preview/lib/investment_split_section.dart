part of 'main.dart';

/// Forward split only: quantity changes, while every lot's cost stays fixed.
class _InvestmentSplitSection extends StatefulWidget {
  const _InvestmentSplitSection({
    required this.engine,
    required this.buys,
    required this.privacy,
    required this.otherPending,
    required this.onSaved,
  });

  final PreviewEngine engine;
  final List<InvestmentBuyFact> buys;
  final PrivacyMode privacy;
  final bool otherPending;
  final Future<void> Function() onSaved;

  @override
  State<_InvestmentSplitSection> createState() =>
      _InvestmentSplitSectionState();
}

class _InvestmentSplitSectionState extends State<_InvestmentSplitSection> {
  final _date = TextEditingController();
  final _newShares = TextEditingController();
  final _oldShares = TextEditingController(text: '1');
  PublicId? _buyId;
  List<InvestmentHoldingLot> _lots = const [];
  List<InvestmentSplitFact> _saved = const [];
  BusinessDate? _lastSaleDate;
  bool _lotsReady = false;
  bool _pending = false;
  bool _dividendPending = false;
  bool _busy = false;
  String? _message;
  StockSplitPreview? _review;
  int _request = 0;
  int _lotRequest = 0;

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

  bool get _canEdit =>
      !_busy &&
      !_pending &&
      !_dividendPending &&
      !widget.otherPending &&
      widget.engine.isUnlocked &&
      widget.privacy != PrivacyMode.hidden;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _date.text =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant _InvestmentSplitSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.engine, oldWidget.engine)) {
      _request++;
      _lotRequest++;
      _saved = const [];
      _buyId = null;
      _lots = const [];
      _lotsReady = false;
      _pending = false;
      _review = null;
      unawaited(_load());
    } else if (!_positions.any((fact) => fact.preview.id == _buyId)) {
      _buyId = null;
      _lots = const [];
      _lotsReady = false;
      _review = null;
    }
    if (!widget.engine.isUnlocked || widget.privacy == PrivacyMode.hidden) {
      _request++;
      _lotRequest++;
      _review = null;
    }
  }

  @override
  void dispose() {
    _request++;
    _lotRequest++;
    for (final controller in [_date, _newShares, _oldShares]) {
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
      final saved = await widget.engine.investmentSplits();
      final pending = await widget.engine.hasPendingInvestmentSplit();
      final dividendPending = await widget.engine
          .hasPendingInvestmentDividend();
      if (!mounted || request != _request || !widget.engine.isUnlocked) return;
      setState(() {
        _saved = saved;
        _pending = pending;
        _dividendPending = dividendPending;
      });
    } catch (_) {
      if (mounted && request == _request) {
        setState(() => _message = '無法核對拆股資料；請保留資料並稍後重試。');
      }
    }
  }

  Future<void> _loadLots() async {
    final selected = _selected;
    final request = ++_lotRequest;
    setState(() {
      _lotsReady = false;
      _lots = const [];
      _lastSaleDate = null;
      _review = null;
    });
    if (selected == null) return;
    try {
      final lots = await widget.engine.investmentHoldingLots(
        selected.account.id,
        selected.instrument.id,
      );
      final sales = await widget.engine.investmentSales(
        selected.account.id,
        selected.instrument.id,
      );
      if (!mounted ||
          request != _lotRequest ||
          !widget.engine.isUnlocked ||
          widget.privacy == PrivacyMode.hidden) {
        return;
      }
      setState(() {
        _lots = lots;
        _lastSaleDate = sales.isEmpty ? null : sales.last.preview.tradedOn;
        _lotsReady = true;
      });
    } catch (_) {
      if (mounted && request == _lotRequest) {
        setState(() => _message = '無法核對目前持股；請稍後重試。');
      }
    }
  }

  void _prepare() {
    if (!_canEdit || !_lotsReady) return;
    try {
      final buy = _selected;
      if (buy == null || _lots.isEmpty) throw const FormatException();
      final effectiveOn = BusinessDate.parse(_date.text.trim());
      if (_lastSaleDate != null && effectiveOn.compareTo(_lastSaleDate!) <= 0) {
        throw const FormatException();
      }
      final positionSplits = _saved.where(
        (fact) =>
            fact.preview.account.id == buy.account.id &&
            fact.preview.instrument.id == buy.instrument.id,
      );
      if (positionSplits.isNotEmpty &&
          effectiveOn.compareTo(positionSplits.last.preview.effectiveOn) <= 0) {
        throw const FormatException();
      }
      final preview = StockSplitPreview.create(
        id: PublicId.generate(),
        operation: OperationKey(
          widget.engine.workspace,
          OperationId(PublicId.generate()),
        ),
        effectiveOn: effectiveOn,
        broker: buy.broker,
        account: buy.account,
        instrument: buy.instrument,
        newShares: int.parse(_newShares.text.trim()),
        oldShares: int.parse(_oldShares.text.trim()),
        lots: _lots,
      );
      setState(() {
        _review = preview;
        _message = null;
      });
    } catch (_) {
      setState(() {
        _review = null;
        _message = '請核對生效日、正向比例與全部持股；不可回填而改寫既有賣出。';
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
      await widget.engine.submitInvestmentSplit(preview);
      if (!mounted || request != _request) return;
      setState(() {
        _review = null;
        _message = '拆股與各筆持股數量已一併保存；成本與現金不變。';
      });
      await _load();
      await _loadLots();
      await widget.onSaved();
    } catch (_) {
      if (mounted && request == _request) {
        setState(() {
          _review = null;
          _message = '結果尚待確認；請重試同一筆拆股，不要另建新拆股。';
        });
        await _load();
        await widget.onSaved();
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
      await widget.engine.retryPendingInvestmentSplit();
      if (!mounted || request != _request) return;
      setState(() => _message = '已核對並保存待確認拆股。');
      await _load();
      await _loadLots();
      await widget.onSaved();
    } catch (_) {
      if (mounted && request == _request) {
        setState(() => _message = '拆股仍待核對；請保留資料並稍後重試。');
        await widget.onSaved();
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
    final review = _review;
    return ExpansionTile(
      key: const ValueKey('investment-split-section'),
      title: const Text('正向拆股'),
      subtitle: const Text('只變更股數；不記現金或新消費，總成本不變。'),
      children: [
        const Text('不可回填而改寫既有賣出；僅支援無現金找零的正向拆股。'),
        if (_pending) ...[
          const Text('上一筆拆股結果待確認，請先重試同一筆。'),
          TextButton(
            key: const ValueKey('retry-investment-split'),
            onPressed: _busy ? null : _retry,
            child: const Text('核對並重試拆股'),
          ),
        ],
        if (_positions.isEmpty)
          const Text('請先記錄買入，才可選擇投資帳戶與商品。')
        else
          DropdownButtonFormField<PublicId>(
            key: const ValueKey('investment-split-position'),
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
                ? (id) {
                    setState(() => _buyId = id);
                    unawaited(_loadLots());
                  }
                : null,
          ),
        if (selected != null) ...[
          if (!_lotsReady)
            const Text('核對目前持股中…')
          else if (_lots.isEmpty)
            const Text('目前沒有可拆分的持股。')
          else
            Text('目前持股 ${_lots.length} 筆；全部數量都會依比例變更。'),
          for (final (key, label, controller) in [
            ('investment-split-date', '生效日 YYYY-MM-DD', _date),
            ('investment-split-new', '拆股後股數，例如 2', _newShares),
            ('investment-split-old', '拆股前股數，例如 1', _oldShares),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TextField(
                key: ValueKey(key),
                controller: controller,
                enabled: _canEdit,
                keyboardType: key == 'investment-split-date'
                    ? TextInputType.datetime
                    : TextInputType.number,
                onChanged: (_) => setState(() => _review = null),
                decoration: InputDecoration(labelText: label),
              ),
            ),
          FilledButton(
            key: const ValueKey('review-investment-split'),
            onPressed: _canEdit && _lotsReady && _lots.isNotEmpty
                ? _prepare
                : null,
            child: const Text('檢查拆股結果'),
          ),
          if (review != null) ...[
            Text(
              '${review.effectiveOn} · ${review.newShares} 換 ${review.oldShares}',
            ),
            for (final change in review.lots)
              Text(
                '${change.before.remainingQuantity} → ${change.afterQuantity} 股；成本 ${change.cost.majorText} ${change.cost.currency.code} 不變',
              ),
            const Text('確認後一併保存拆股事實與每筆持股數量；現金不變。'),
            FilledButton(
              key: const ValueKey('save-investment-split'),
              onPressed: _canEdit ? _save : null,
              child: const Text('確認並保存拆股'),
            ),
          ],
        ],
        Text('已記錄拆股', style: Theme.of(context).textTheme.titleMedium),
        for (final fact in _saved)
          ListTile(
            key: ValueKey('investment-split-${fact.preview.id.value}'),
            title: Text(
              '${fact.preview.effectiveOn} · ${fact.preview.instrument.marketCode}:${fact.preview.instrument.symbol}',
            ),
            subtitle: Text(
              '${fact.preview.newShares} 換 ${fact.preview.oldShares} · 總成本不變',
            ),
          ),
        if (_message != null)
          Text(_message!, key: const ValueKey('investment-split-message')),
      ],
    );
  }
}
