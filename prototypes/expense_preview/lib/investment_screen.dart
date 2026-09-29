part of 'main.dart';

/// A buy is reviewed as a cash debit and a new acquisition lot before it is
/// submitted. No market price, gain, or tax basis is inferred here.
class _InvestmentScreen extends StatefulWidget {
  const _InvestmentScreen({
    required this.engine,
    required this.accounts,
    required this.privacy,
  });

  final PreviewEngine engine;
  final List<AccountSummary> accounts;
  final PrivacyMode privacy;

  @override
  State<_InvestmentScreen> createState() => _InvestmentScreenState();
}

class _InvestmentScreenState extends State<_InvestmentScreen> {
  final _brokerName = TextEditingController();
  final _investmentAccountName = TextEditingController();
  final _market = TextEditingController();
  final _symbol = TextEditingController();
  final _instrumentName = TextEditingController();
  final _date = TextEditingController();
  final _quantity = TextEditingController();
  final _unitPrice = TextEditingController();
  final _gross = TextEditingController();
  final _fee = TextEditingController(text: '0');
  final _tax = TextEditingController(text: '0');

  List<InvestmentBuyFact> _saved = const [];
  List<AccountSummary> _currentAccounts = const [];
  PublicId? _existingBuyId;
  PublicId? _fundingId;
  InstrumentKind _kind = InstrumentKind.stock;
  InvestmentBuyPreview? _review;
  String? _message;
  bool _busy = false;
  bool _pending = false;
  bool _loaded = false;
  int _request = 0;

  List<AccountSummary> get _fundingAccounts => _currentAccounts
      .where(
        (row) =>
            row.account.state == AccountState.active &&
            (row.account.kind == AccountKind.cash ||
                row.account.kind == AccountKind.bank),
      )
      .toList(growable: false);

  InvestmentBuyFact? get _existing =>
      _saved.where((row) => row.preview.id == _existingBuyId).firstOrNull;

  AccountSummary? get _funding =>
      _fundingAccounts.where((row) => row.account.id == _fundingId).firstOrNull;

  @override
  void initState() {
    super.initState();
    _currentAccounts = widget.accounts;
    final now = DateTime.now();
    _date.text =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    _fundingId = _fundingAccounts.firstOrNull?.account.id;
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant _InvestmentScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.engine, oldWidget.engine)) {
      _request++;
      _saved = const [];
      _currentAccounts = widget.accounts;
      _existingBuyId = null;
      _review = null;
      _pending = false;
      _loaded = false;
      _fundingId = _fundingAccounts.firstOrNull?.account.id;
      unawaited(_load());
      return;
    }
    if (!widget.engine.isUnlocked || widget.privacy == PrivacyMode.hidden) {
      _request++;
      _review = null;
    }
    if (!_fundingAccounts.any((row) => row.account.id == _fundingId)) {
      _fundingId = _fundingAccounts.firstOrNull?.account.id;
      _review = null;
    }
  }

  @override
  void dispose() {
    _request++;
    for (final controller in [
      _brokerName,
      _investmentAccountName,
      _market,
      _symbol,
      _instrumentName,
      _date,
      _quantity,
      _unitPrice,
      _gross,
      _fee,
      _tax,
    ]) {
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
      final accounts = await widget.engine.accounts();
      final saved = await widget.engine.investmentBuys();
      final pending = await widget.engine.hasPendingInvestmentBuy();
      if (!mounted ||
          request != _request ||
          !widget.engine.isUnlocked ||
          widget.privacy == PrivacyMode.hidden) {
        return;
      }
      setState(() {
        _currentAccounts = accounts;
        _saved = saved;
        _pending = pending;
        _loaded = true;
        if (!_fundingAccounts.any((row) => row.account.id == _fundingId)) {
          _fundingId = _fundingAccounts.firstOrNull?.account.id;
          _review = null;
        }
        if (!saved.any((row) => row.preview.id == _existingBuyId)) {
          _existingBuyId = null;
        }
      });
    } catch (_) {
      if (mounted &&
          request == _request &&
          widget.engine.isUnlocked &&
          widget.privacy != PrivacyMode.hidden) {
        setState(() => _message = '無法讀取投資紀錄；請保留資料，稍後重試。');
      }
    }
  }

  void _changed(String _) => setState(() {
    _review = null;
    _message = null;
  });

  void _selectExisting(PublicId? buyId) {
    setState(() {
      _existingBuyId = buyId;
      _review = null;
      _message = null;
      final preview = _existing?.preview;
      if (preview != null) {
        _brokerName.text = preview.broker.name;
        _investmentAccountName.text = preview.account.name;
        _market.text = preview.instrument.marketCode;
        _symbol.text = preview.instrument.symbol;
        _instrumentName.text = preview.instrument.name;
        _kind = preview.instrument.kind;
        _fundingId = preview.funding.id;
      } else {
        _brokerName.clear();
        _investmentAccountName.clear();
        _market.clear();
        _symbol.clear();
        _instrumentName.clear();
        _kind = InstrumentKind.stock;
        _fundingId = _fundingAccounts.firstOrNull?.account.id;
      }
    });
  }

  void _prepare() {
    if (_busy ||
        _pending ||
        !widget.engine.isUnlocked ||
        widget.privacy == PrivacyMode.hidden) {
      return;
    }
    try {
      final funding = _funding?.account;
      if (funding == null) throw const FormatException();
      final existing = _existing?.preview;
      if (existing != null && existing.funding.id != funding.id) {
        throw const FormatException();
      }
      final workspace = widget.engine.workspace;
      final currency = funding.currency;
      final brokerName = _brokerName.text.trim();
      final matchingBroker = _saved
          .where((row) => row.preview.broker.name == brokerName)
          .map((row) => row.preview.broker)
          .firstOrNull;
      final broker =
          existing?.broker ??
          matchingBroker ??
          BrokerIdentity(
            id: PublicId.generate(),
            workspace: workspace,
            name: brokerName,
          );
      final account =
          existing?.account ??
          InvestmentAccount(
            id: PublicId.generate(),
            workspace: workspace,
            brokerId: broker.id,
            fundingCashAccountId: funding.id,
            name: _investmentAccountName.text.trim(),
            expectedVersion: 1,
          );
      final market = _market.text.trim().toUpperCase();
      final symbol = _symbol.text.trim().toUpperCase();
      final instrumentName = _instrumentName.text.trim();
      final matchingInstrument = _saved
          .where(
            (row) =>
                row.preview.instrument.marketCode == market &&
                row.preview.instrument.symbol == symbol,
          )
          .map((row) => row.preview.instrument)
          .firstOrNull;
      if (existing == null &&
          matchingInstrument != null &&
          (matchingInstrument.kind != _kind ||
              matchingInstrument.name != instrumentName ||
              matchingInstrument.tradingCurrency != currency)) {
        throw const FormatException();
      }
      final instrument =
          existing?.instrument ??
          matchingInstrument ??
          InvestmentInstrument(
            id: PublicId.generate(),
            kind: _kind,
            marketCode: market,
            symbol: symbol,
            name: instrumentName,
            tradingCurrency: currency,
          );
      if (instrument.tradingCurrency != currency) {
        throw const InvestmentException(InvestmentError.currencyMismatch);
      }
      final tradedOn = BusinessDate.parse(_date.text.trim());
      if (tradedOn.compareTo(funding.openedOn) < 0) {
        throw const FormatException();
      }
      final preview = InvestmentBuyPreview.create(
        id: PublicId.generate(),
        lotId: PublicId.generate(),
        operation: OperationKey(workspace, OperationId(PublicId.generate())),
        tradedOn: tradedOn,
        broker: broker,
        account: account,
        instrument: instrument,
        funding: FundingCashAccount(
          id: funding.id,
          workspace: workspace,
          currency: currency,
          expectedVersion: funding.version,
        ),
        quantity: ShareQuantity.parse(_quantity.text.trim()),
        unitPrice: ShareUnitPrice.parse(currency, _unitPrice.text.trim()),
        executedGross: Money.parse(currency, _gross.text.trim()),
        fee: Money.parse(currency, _fee.text.trim()),
        tax: Money.parse(currency, _tax.text.trim()),
      );
      setState(() {
        _review = preview;
        _message = null;
      });
    } catch (_) {
      setState(() {
        _review = null;
        _message =
            '請核對帳戶與幣別、日期、商品身分，以及股數 × 單價四捨五入後的成交總額；不進行自動換匯。既有商品請使用相同名稱與類型。';
      });
    }
  }

  Future<void> _save() async {
    final preview = _review;
    if (preview == null ||
        _busy ||
        _pending ||
        !widget.engine.isUnlocked ||
        widget.privacy == PrivacyMode.hidden) {
      return;
    }
    final request = ++_request;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await widget.engine.submitInvestmentBuy(preview);
      if (!mounted ||
          request != _request ||
          !widget.engine.isUnlocked ||
          widget.privacy == PrivacyMode.hidden) {
        return;
      }
      setState(() {
        _review = null;
        _message = '已記錄買入與銀行／現金扣款；成交紀錄不代表即時市值。';
      });
      await _load();
    } catch (_) {
      if (mounted &&
          request == _request &&
          widget.engine.isUnlocked &&
          widget.privacy != PrivacyMode.hidden) {
        setState(() => _message = '尚未能確認買入結果；請核對紀錄並重試同一筆，勿另建重複交易。');
        await _load();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _retry() async {
    if (_busy ||
        !_pending ||
        !widget.engine.isUnlocked ||
        widget.privacy == PrivacyMode.hidden) {
      return;
    }
    final request = ++_request;
    setState(() => _busy = true);
    try {
      await widget.engine.retryPendingInvestmentBuy();
      if (mounted &&
          request == _request &&
          widget.engine.isUnlocked &&
          widget.privacy != PrivacyMode.hidden) {
        setState(() {
          _review = null;
          _message = '已核對待確認買入；請查看下方紀錄。';
        });
        await _load();
      }
    } catch (_) {
      if (mounted &&
          request == _request &&
          widget.engine.isUnlocked &&
          widget.privacy != PrivacyMode.hidden) {
        setState(() => _message = '買入仍待核對；請保留資料，稍後重試。');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.engine.isUnlocked) return const SizedBox.shrink();
    if (widget.privacy == PrivacyMode.hidden) {
      return const Text('目前已隱藏投資資料；顯示資料後才能操作。');
    }
    final existing = _existing?.preview;
    final funding = _funding?.account;
    final review = _review;
    final saved = [..._saved]
      ..sort((a, b) => b.preview.tradedOn.compareTo(a.preview.tradedOn));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('投資買入', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        const Text('手動記錄股票或 ETF 的實際買入。只扣同幣別現金／銀行帳戶；不提供報價、賣出或損益估值。'),
        const SizedBox(height: 12),
        if (!_loaded) const CircularProgressIndicator(),
        if (_loaded && _fundingAccounts.isEmpty) const Text('請先建立可用的現金或銀行帳戶。'),
        if (_loaded && _fundingAccounts.isNotEmpty) ...[
          if (_pending) ...[
            const Text('前一筆買入尚待核對，請先重試同一筆。'),
            TextButton(
              key: const ValueKey('retry-investment-buy'),
              onPressed: _busy ? null : _retry,
              child: const Text('核對並重試'),
            ),
          ],
          DropdownButtonFormField<PublicId>(
            key: const ValueKey('investment-existing'),
            initialValue: _existingBuyId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: '投資帳戶與商品'),
            hint: const Text('新增券商、投資帳戶與商品'),
            items: [
              const DropdownMenuItem<PublicId>(
                value: null,
                child: Text('新增券商、投資帳戶與商品'),
              ),
              for (final fact in _saved)
                DropdownMenuItem(
                  value: fact.preview.id,
                  child: Text(
                    '${fact.preview.account.name} · ${fact.preview.instrument.marketCode}:${fact.preview.instrument.symbol}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: _busy || _pending ? null : _selectExisting,
          ),
          const SizedBox(height: 8),
          for (final (key, label, controller) in [
            ('investment-broker', '券商名稱', _brokerName),
            ('investment-account', '投資帳戶名稱', _investmentAccountName),
            ('investment-market', '市場代碼（例如 XNAS）', _market),
            ('investment-symbol', '商品代碼', _symbol),
            ('investment-name', '商品名稱', _instrumentName),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TextField(
                key: ValueKey(key),
                controller: controller,
                enabled: !_busy && !_pending && existing == null,
                onChanged: _changed,
                decoration: InputDecoration(labelText: label),
              ),
            ),
          DropdownButtonFormField<InstrumentKind>(
            key: const ValueKey('investment-kind'),
            initialValue: _kind,
            decoration: const InputDecoration(labelText: '商品類型'),
            items: const [
              DropdownMenuItem(value: InstrumentKind.stock, child: Text('股票')),
              DropdownMenuItem(value: InstrumentKind.etf, child: Text('ETF')),
            ],
            onChanged: _busy || _pending || existing != null
                ? null
                : (value) => setState(() {
                    _kind = value ?? InstrumentKind.stock;
                    _review = null;
                  }),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<PublicId>(
            key: const ValueKey('investment-funding'),
            initialValue:
                existing == null ||
                    _fundingAccounts.any(
                      (row) => row.account.id == existing.funding.id,
                    )
                ? _fundingId
                : null,
            isExpanded: true,
            decoration: const InputDecoration(labelText: '扣款帳戶'),
            items: [
              for (final row in _fundingAccounts.where(
                (row) =>
                    existing == null || row.account.id == existing.funding.id,
              ))
                DropdownMenuItem(
                  value: row.account.id,
                  child: Text(
                    '${row.account.name} · ${row.account.currency.code}',
                  ),
                ),
            ],
            onChanged: _busy || _pending || existing != null
                ? null
                : (value) => setState(() {
                    _fundingId = value;
                    _review = null;
                  }),
          ),
          if (existing != null && funding == null)
            const Text('原扣款帳戶目前不可用，無法再用此投資帳戶買入。'),
          const SizedBox(height: 8),
          for (final (key, label, controller) in [
            ('investment-date', '交易日期 YYYY-MM-DD', _date),
            ('investment-quantity', '股數（最多 12 位小數）', _quantity),
            ('investment-price', '每股成交價', _unitPrice),
            ('investment-gross', '實際成交總額', _gross),
            ('investment-fee', '手續費（可為 0）', _fee),
            ('investment-tax', '稅額（可為 0）', _tax),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TextField(
                key: ValueKey(key),
                controller: controller,
                enabled: !_busy && !_pending,
                keyboardType: key == 'investment-date'
                    ? TextInputType.datetime
                    : const TextInputType.numberWithOptions(decimal: true),
                onChanged: _changed,
                decoration: InputDecoration(labelText: label),
              ),
            ),
          FilledButton(
            key: const ValueKey('review-investment-buy'),
            onPressed: _busy || _pending || funding == null ? null : _prepare,
            child: const Text('檢查買入與扣款'),
          ),
          if (review != null) ...[
            const SizedBox(height: 12),
            Text(
              '${review.tradedOn} · ${review.instrument.marketCode}:${review.instrument.symbol} · ${review.quantity} 股',
            ),
            Text(
              '成交 ${review.gross.majorText} + 手續費 ${review.fee.majorText} + 稅 ${review.tax.majorText} = 扣款 ${review.cashDebit.majorText} ${review.cashDebit.currency.code}',
              key: const ValueKey('investment-cash-preview'),
            ),
            const Text('確認後一次記錄扣款與持股批次；買入不列為日常消費。'),
            FilledButton(
              key: const ValueKey('save-investment-buy'),
              onPressed: _busy ? null : _save,
              child: const Text('確認買入並扣款'),
            ),
          ],
        ],
        const SizedBox(height: 16),
        Text('已記錄買入', style: Theme.of(context).textTheme.titleMedium),
        if (_loaded && saved.isEmpty) const Text('尚無投資買入紀錄。'),
        for (final fact in saved)
          ListTile(
            key: ValueKey('investment-buy-${fact.preview.id.value}'),
            title: Text(
              '${fact.preview.instrument.marketCode}:${fact.preview.instrument.symbol} · ${fact.preview.tradedOn}',
            ),
            subtitle: Text(
              '${fact.preview.account.name} · 持股批次 ${fact.preview.lot.quantity} 股',
            ),
            trailing: Text(
              '實付 ${fact.preview.lot.acquisitionCashCost.majorText} ${fact.preview.cashDebit.currency.code}',
            ),
          ),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_message!, key: const ValueKey('investment-message')),
          ),
      ],
    );
  }
}
