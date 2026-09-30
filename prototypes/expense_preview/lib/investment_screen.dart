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
  final _sellDate = TextEditingController();
  final _sellQuantity = TextEditingController();
  final _sellUnitPrice = TextEditingController();
  final _sellGross = TextEditingController();
  final _sellFee = TextEditingController(text: '0');
  final _sellTax = TextEditingController(text: '0');

  List<InvestmentBuyFact> _saved = const [];
  List<InvestmentSellFact> _savedSales = const [];
  List<InvestmentHoldingLot> _sellLots = const [];
  List<AccountSummary> _currentAccounts = const [];
  PublicId? _existingBuyId;
  PublicId? _sellBuyId;
  PublicId? _fundingId;
  InstrumentKind _kind = InstrumentKind.stock;
  InvestmentCostMethod _sellMethod = InvestmentCostMethod.fifo;
  InvestmentBuyPreview? _review;
  InvestmentSellPreview? _sellReview;
  String? _message;
  String? _sellMessage;
  bool _busy = false;
  bool _pending = false;
  bool _sellPending = false;
  bool _dividendPending = false;
  bool _splitPending = false;
  bool _sellLotsReady = false;
  bool _loaded = false;
  int _request = 0;
  int _sellRequest = 0;

  bool get _hasPendingOperation =>
      _pending || _sellPending || _dividendPending || _splitPending;

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

  InvestmentBuyFact? get _selectedSellBuy =>
      _saved.where((row) => row.preview.id == _sellBuyId).firstOrNull;

  AccountSummary? get _sellFunding {
    final preview = _selectedSellBuy?.preview;
    if (preview == null) return null;
    return _fundingAccounts
        .where(
          (row) =>
              row.account.id == preview.funding.id &&
              row.account.currency == preview.instrument.tradingCurrency,
        )
        .firstOrNull;
  }

  List<InvestmentBuyFact> get _sellChoices {
    final seen = <String>{};
    return _saved
        .where((fact) {
          final preview = fact.preview;
          return seen.add('${preview.account.id}|${preview.instrument.id}');
        })
        .toList(growable: false);
  }

  @override
  void initState() {
    super.initState();
    _currentAccounts = widget.accounts;
    final now = DateTime.now();
    _date.text =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    _sellDate.text = _date.text;
    _fundingId = _fundingAccounts.firstOrNull?.account.id;
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant _InvestmentScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.engine, oldWidget.engine)) {
      _request++;
      _saved = const [];
      _savedSales = const [];
      _sellLots = const [];
      _currentAccounts = widget.accounts;
      _existingBuyId = null;
      _sellBuyId = null;
      _review = null;
      _sellReview = null;
      _pending = false;
      _sellPending = false;
      _dividendPending = false;
      _splitPending = false;
      _sellLotsReady = false;
      _loaded = false;
      _fundingId = _fundingAccounts.firstOrNull?.account.id;
      unawaited(_load());
      return;
    }
    if (!widget.engine.isUnlocked || widget.privacy == PrivacyMode.hidden) {
      _request++;
      _sellRequest++;
      _review = null;
      _sellReview = null;
    }
    if (!_fundingAccounts.any((row) => row.account.id == _fundingId)) {
      _fundingId = _fundingAccounts.firstOrNull?.account.id;
      _review = null;
    }
  }

  @override
  void dispose() {
    _request++;
    _sellRequest++;
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
      _sellDate,
      _sellQuantity,
      _sellUnitPrice,
      _sellGross,
      _sellFee,
      _sellTax,
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
      final sellPending = widget.engine.capabilities.investmentSales
          ? await widget.engine.hasPendingInvestmentSell()
          : false;
      final dividendPending = widget.engine.capabilities.investmentDividends
          ? await widget.engine.hasPendingInvestmentDividend()
          : false;
      final splitPending = widget.engine.capabilities.investmentSplits
          ? await widget.engine.hasPendingInvestmentSplit()
          : false;
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
        _sellPending = sellPending;
        _dividendPending = dividendPending;
        _splitPending = splitPending;
        _loaded = true;
        if (!_fundingAccounts.any((row) => row.account.id == _fundingId)) {
          _fundingId = _fundingAccounts.firstOrNull?.account.id;
          _review = null;
        }
        if (!saved.any((row) => row.preview.id == _existingBuyId)) {
          _existingBuyId = null;
        }
        if (!saved.any((row) => row.preview.id == _sellBuyId)) {
          _sellBuyId = null;
          _sellLots = const [];
          _savedSales = const [];
          _sellLotsReady = false;
          _sellReview = null;
        }
      });
      if (_sellBuyId != null && widget.engine.capabilities.investmentSales) {
        await _loadSellLots();
      }
    } catch (_) {
      if (mounted &&
          request == _request &&
          widget.engine.isUnlocked &&
          widget.privacy != PrivacyMode.hidden) {
        setState(() => _message = '無法讀取投資紀錄；請保留資料，稍後重試。');
      }
    }
  }

  Future<void> _loadSellLots() async {
    final request = ++_sellRequest;
    final selected = _selectedSellBuy?.preview;
    if (selected == null ||
        !widget.engine.isUnlocked ||
        widget.privacy == PrivacyMode.hidden) {
      return;
    }
    setState(() => _sellLotsReady = false);
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
          request != _sellRequest ||
          _sellBuyId != selected.id ||
          !widget.engine.isUnlocked ||
          widget.privacy == PrivacyMode.hidden) {
        return;
      }
      setState(() {
        _sellLots = lots;
        _savedSales = sales;
        if (sales.isNotEmpty) {
          _sellMethod = sales.first.preview.costMethod;
        }
        _sellLotsReady = true;
        _sellReview = null;
      });
    } catch (_) {
      if (mounted &&
          request == _sellRequest &&
          widget.engine.isUnlocked &&
          widget.privacy != PrivacyMode.hidden) {
        setState(() {
          _sellLots = const [];
          _savedSales = const [];
          _sellLotsReady = false;
          _sellReview = null;
          _sellMessage = '無法核對可賣持股；請保留資料並重新讀取。';
        });
      }
    }
  }

  void _selectSellBuy(PublicId? buyId) {
    setState(() {
      _sellBuyId = buyId;
      _sellReview = null;
      _sellLots = const [];
      _savedSales = const [];
      _sellLotsReady = false;
      _sellMethod = InvestmentCostMethod.fifo;
      _sellMessage = null;
    });
    if (buyId != null) unawaited(_loadSellLots());
  }

  void _sellChanged(String _) => setState(() {
    _sellReview = null;
    _sellMessage = null;
  });

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
        _hasPendingOperation ||
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
        _hasPendingOperation ||
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

  void _prepareSell() {
    if (_busy ||
        _hasPendingOperation ||
        !_sellLotsReady ||
        !widget.engine.isUnlocked ||
        widget.privacy == PrivacyMode.hidden) {
      return;
    }
    try {
      final buy = _selectedSellBuy?.preview;
      final funding = _sellFunding?.account;
      if (buy == null || funding == null || _sellLots.isEmpty) {
        throw const FormatException();
      }
      final date = BusinessDate.parse(_sellDate.text.trim());
      if (date.compareTo(funding.openedOn) < 0) {
        throw const FormatException();
      }
      final currency = buy.instrument.tradingCurrency;
      final workspace = widget.engine.workspace;
      final preview = InvestmentSellPreview.create(
        id: PublicId.generate(),
        operation: OperationKey(workspace, OperationId(PublicId.generate())),
        tradedOn: date,
        broker: buy.broker,
        account: buy.account,
        instrument: buy.instrument,
        funding: FundingCashAccount(
          id: funding.id,
          workspace: workspace,
          currency: funding.currency,
          expectedVersion: funding.version,
        ),
        costMethod: _sellMethod,
        quantity: ShareQuantity.parse(_sellQuantity.text.trim()),
        unitPrice: ShareUnitPrice.parse(currency, _sellUnitPrice.text.trim()),
        executedGross: Money.parse(currency, _sellGross.text.trim()),
        fee: Money.parse(currency, _sellFee.text.trim()),
        tax: Money.parse(currency, _sellTax.text.trim()),
        lots: _sellLots,
      );
      setState(() {
        _sellReview = preview;
        _sellMessage = null;
      });
    } catch (_) {
      setState(() {
        _sellReview = null;
        _sellMessage = '請核對可賣股數、日期、同幣別成交總額及費稅；賣出不可超過目前持股。';
      });
    }
  }

  Future<void> _saveSell() async {
    final preview = _sellReview;
    if (preview == null ||
        _busy ||
        _hasPendingOperation ||
        !widget.engine.isUnlocked ||
        widget.privacy == PrivacyMode.hidden) {
      return;
    }
    final request = ++_request;
    setState(() {
      _busy = true;
      _sellMessage = null;
    });
    try {
      await widget.engine.submitInvestmentSell(preview);
      if (!mounted ||
          request != _request ||
          !widget.engine.isUnlocked ||
          widget.privacy == PrivacyMode.hidden) {
        return;
      }
      setState(() {
        _sellReview = null;
        _sellMessage = '已記錄賣出、持股成本與現金入帳；請核對實際券商成交紀錄。';
      });
      await _load();
    } catch (_) {
      if (mounted &&
          request == _request &&
          widget.engine.isUnlocked &&
          widget.privacy != PrivacyMode.hidden) {
        setState(() {
          _sellReview = null;
          _sellMessage = '尚未能確認賣出結果；請重試同一筆，勿另建重複交易。';
        });
        await _load();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _retrySell() async {
    if (_busy ||
        !_sellPending ||
        !widget.engine.isUnlocked ||
        widget.privacy == PrivacyMode.hidden) {
      return;
    }
    final request = ++_request;
    setState(() => _busy = true);
    try {
      await widget.engine.retryPendingInvestmentSell();
      if (mounted &&
          request == _request &&
          widget.engine.isUnlocked &&
          widget.privacy != PrivacyMode.hidden) {
        setState(() {
          _sellReview = null;
          _sellMessage = '已核對待確認賣出；請查看持股及現金餘額。';
        });
        await _load();
      }
    } catch (_) {
      if (mounted &&
          request == _request &&
          widget.engine.isUnlocked &&
          widget.privacy != PrivacyMode.hidden) {
        setState(() => _sellMessage = '賣出仍待核對；請保留資料，稍後重試。');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _shareUnitsText(BigInt units) {
    final scale = BigInt.from(10).pow(InvestmentSellPreview.quantityScale);
    final whole = units ~/ scale;
    final fractional = units
        .remainder(scale)
        .toString()
        .padLeft(InvestmentSellPreview.quantityScale, '0')
        .replaceFirst(RegExp(r'0+$'), '');
    return fractional.isEmpty ? '$whole' : '$whole.$fractional';
  }

  Widget _sellSection(BuildContext context) {
    final selected = _selectedSellBuy?.preview;
    final funding = _sellFunding?.account;
    final review = _sellReview;
    final quantityUnits = _sellLots.fold<BigInt>(
      BigInt.zero,
      (total, lot) =>
          total +
          lot.remainingQuantity.coefficient *
              BigInt.from(10).pow(
                InvestmentSellPreview.quantityScale -
                    lot.remainingQuantity.scale,
              ),
    );
    final costUnits = _sellLots.fold<BigInt>(
      BigInt.zero,
      (total, lot) => total + lot.remainingCost.minorUnits,
    );
    return ExpansionTile(
      key: const ValueKey('investment-sell-section'),
      title: const Text('賣出持股'),
      subtitle: const Text('依實際成交價賣出；FIFO 或平均成本可供選擇。'),
      children: [
        if (_sellPending) ...[
          const Text('前一筆賣出尚待核對，請先重試同一筆。'),
          TextButton(
            key: const ValueKey('retry-investment-sell'),
            onPressed: _busy ? null : _retrySell,
            child: const Text('核對並重試賣出'),
          ),
        ],
        if (_sellChoices.isEmpty)
          const Text('請先記錄買入，才能選擇賣出的投資帳戶與商品。')
        else
          DropdownButtonFormField<PublicId>(
            key: const ValueKey('investment-sell-position'),
            initialValue: _sellBuyId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: '賣出哪個投資帳戶與商品'),
            items: [
              for (final fact in _sellChoices)
                DropdownMenuItem(
                  value: fact.preview.id,
                  child: Text(
                    '${fact.preview.account.name} · ${fact.preview.instrument.marketCode}:${fact.preview.instrument.symbol}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: _busy || _hasPendingOperation ? null : _selectSellBuy,
          ),
        if (selected != null) ...[
          const SizedBox(height: 8),
          if (!_sellLotsReady)
            const Text('正在核對可賣持股與批次…')
          else if (_sellLots.isEmpty)
            const Text('此商品目前沒有可賣持股。')
          else ...[
            Text(
              '可賣 ${_shareUnitsText(quantityUnits)} 股 · 尚餘取得成本 ${Money(selected.instrument.tradingCurrency, costUnits).majorText} ${selected.instrument.tradingCurrency.code}',
              key: const ValueKey('investment-sell-holding'),
            ),
            for (final lot in _sellLots)
              ListTile(
                key: ValueKey('investment-holding-${lot.id.value}'),
                title: Text('${lot.acquiredOn} · ${lot.remainingQuantity} 股'),
                subtitle: Text(
                  '批次成本 ${lot.remainingCost.majorText} ${lot.remainingCost.currency.code}',
                ),
              ),
          ],
          if (funding == null) const Text('原入帳帳戶目前不可用，無法賣出。'),
          if (funding != null)
            Text('現金入帳：${funding.name} · ${funding.currency.code}'),
          const SizedBox(height: 8),
          KeyedSubtree(
            key: ValueKey(
              'investment-sell-method-field-${_sellBuyId?.value}-${_sellMethod.name}',
            ),
            child: DropdownButtonFormField<InvestmentCostMethod>(
              key: const ValueKey('investment-sell-method'),
              initialValue: _sellMethod,
              decoration: const InputDecoration(labelText: '持股成本計算方式'),
              items: const [
                DropdownMenuItem(
                  value: InvestmentCostMethod.fifo,
                  child: Text('先進先出（FIFO）'),
                ),
                DropdownMenuItem(
                  value: InvestmentCostMethod.averageCost,
                  child: Text('平均成本'),
                ),
              ],
              onChanged: _busy || _hasPendingOperation || _savedSales.isNotEmpty
                  ? null
                  : (value) => setState(() {
                      _sellMethod = value ?? InvestmentCostMethod.fifo;
                      _sellReview = null;
                    }),
            ),
          ),
          if (_savedSales.isNotEmpty) const Text('此持倉已有賣出紀錄；後續賣出須沿用相同成本法。'),
          const SizedBox(height: 8),
          for (final (key, label, controller) in [
            ('investment-sell-date', '賣出日期 YYYY-MM-DD', _sellDate),
            ('investment-sell-quantity', '賣出股數', _sellQuantity),
            ('investment-sell-price', '每股成交價', _sellUnitPrice),
            ('investment-sell-gross', '實際成交總額', _sellGross),
            ('investment-sell-fee', '手續費（可為 0）', _sellFee),
            ('investment-sell-tax', '稅額（可為 0）', _sellTax),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TextField(
                key: ValueKey(key),
                controller: controller,
                enabled: !_busy && !_hasPendingOperation,
                keyboardType: key == 'investment-sell-date'
                    ? TextInputType.datetime
                    : const TextInputType.numberWithOptions(decimal: true),
                onChanged: _sellChanged,
                decoration: InputDecoration(labelText: label),
              ),
            ),
          FilledButton(
            key: const ValueKey('review-investment-sell'),
            onPressed:
                _busy ||
                    _hasPendingOperation ||
                    !_sellLotsReady ||
                    _sellLots.isEmpty ||
                    funding == null
                ? null
                : _prepareSell,
            child: const Text('檢查賣出、成本與入帳'),
          ),
          if (review != null) ...[
            const SizedBox(height: 12),
            Text(
              '${review.tradedOn} · ${review.instrument.marketCode}:${review.instrument.symbol} · 賣出 ${review.quantity} 股',
            ),
            Text(
              '成交 ${review.gross.majorText} − 手續費 ${review.fee.majorText} − 稅 ${review.tax.majorText} = 現金入帳 ${review.netCashCredit.majorText} ${review.netCashCredit.currency.code}',
              key: const ValueKey('investment-sell-cash-preview'),
            ),
            Text(
              '${review.costMethod == InvestmentCostMethod.fifo ? '先進先出' : '平均成本'} · 分攤取得成本 ${review.allocatedCost.majorText} · 已實現損益 ${review.realizedResult.majorText} ${review.realizedResult.currency.code}',
              key: const ValueKey('investment-sell-result-preview'),
            ),
            for (final allocation in review.allocations.where(
              (allocation) => allocation.soldQuantityUnits > BigInt.zero,
            ))
              Text(
                '批次 ${allocation.lot.acquiredOn}：賣出 ${_shareUnitsText(allocation.soldQuantityUnits)} 股，分攤成本 ${allocation.allocatedSaleCost.majorText}',
              ),
            const Text('確認後同時更新持股批次與現金；本地成本估算不等於券商稅務報表。'),
            FilledButton(
              key: const ValueKey('save-investment-sell'),
              onPressed: _busy ? null : _saveSell,
              child: const Text('確認賣出並入帳'),
            ),
          ],
          const SizedBox(height: 12),
          Text('已記錄賣出', style: Theme.of(context).textTheme.titleMedium),
          if (_sellLotsReady && _savedSales.isEmpty) const Text('此商品尚無賣出紀錄。'),
          for (final fact in _savedSales)
            ListTile(
              key: ValueKey('investment-sell-${fact.preview.id.value}'),
              title: Text(
                '${fact.preview.tradedOn} · ${fact.preview.quantity} 股',
              ),
              subtitle: Text(
                '${fact.preview.costMethod == InvestmentCostMethod.fifo ? 'FIFO' : '平均成本'} · 已實現損益 ${fact.preview.realizedResult.majorText}',
              ),
              trailing: Text(
                '入帳 ${fact.preview.netCashCredit.majorText} ${fact.preview.netCashCredit.currency.code}',
              ),
            ),
        ],
        if (_sellMessage != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _sellMessage!,
              key: const ValueKey('investment-sell-message'),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.engine.isUnlocked) return const SizedBox.shrink();
    if (widget.privacy == PrivacyMode.hidden) {
      return const Text('目前已隱藏投資資料；顯示資料後才能操作。');
    }
    final existing = _existing?.preview;
    final quoted = _selectedSellBuy?.preview ?? existing;
    final funding = _funding?.account;
    final review = _review;
    final saved = [..._saved]
      ..sort((a, b) => b.preview.tradedOn.compareTo(a.preview.tradedOn));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('投資買入', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(
          widget.engine.capabilities.investmentSales
              ? '手動記錄股票或 ETF 的實際成交，只用同幣別現金／銀行帳戶；可按需查詢部分市場的每日收盤參考價，不提供即時報價或完整績效。'
              : '手動記錄股票或 ETF 的實際買入。只扣同幣別現金／銀行帳戶；不提供報價、賣出或損益估值。',
        ),
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
            onChanged: _busy || _hasPendingOperation ? null : _selectExisting,
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
                enabled: !_busy && !_hasPendingOperation && existing == null,
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
            onChanged: _busy || _hasPendingOperation || existing != null
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
            onChanged: _busy || _hasPendingOperation || existing != null
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
                enabled: !_busy && !_hasPendingOperation,
                keyboardType: key == 'investment-date'
                    ? TextInputType.datetime
                    : const TextInputType.numberWithOptions(decimal: true),
                onChanged: _changed,
                decoration: InputDecoration(labelText: label),
              ),
            ),
          FilledButton(
            key: const ValueKey('review-investment-buy'),
            onPressed: _busy || _hasPendingOperation || funding == null
                ? null
                : _prepare,
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
        if (quoted != null) ...[
          const SizedBox(height: 12),
          MarketQuotePanel(
            key: ValueKey('market-close-${quoted.instrument.id.value}'),
            instrument: quoted.instrument,
            showAmounts: widget.privacy == PrivacyMode.visible,
            investmentAccountId:
                _sellLotsReady &&
                    _selectedSellBuy?.preview.instrument.id ==
                        quoted.instrument.id
                ? quoted.account.id
                : null,
            openLots:
                _sellLotsReady &&
                    _selectedSellBuy?.preview.instrument.id ==
                        quoted.instrument.id
                ? _sellLots
                : null,
          ),
        ],
        if (widget.engine.capabilities.investmentSales) ...[
          const SizedBox(height: 8),
          _sellSection(context),
        ],
        if (widget.engine.capabilities.investmentDividends) ...[
          const SizedBox(height: 8),
          _InvestmentDividendSection(
            engine: widget.engine,
            buys: _saved,
            accounts: _currentAccounts,
            privacy: widget.privacy,
            otherPending: _hasPendingOperation,
            onSaved: _load,
          ),
        ],
        if (widget.engine.capabilities.investmentSplits) ...[
          const SizedBox(height: 8),
          _InvestmentSplitSection(
            engine: widget.engine,
            buys: _saved,
            privacy: widget.privacy,
            otherPending: _hasPendingOperation,
            onSaved: _load,
          ),
        ],
        if (_message != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_message!, key: const ValueKey('investment-message')),
          ),
      ],
    );
  }
}
