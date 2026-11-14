part of 'composer.dart';

// The choices the form opens: amount, day, account, category, holding, merchant, tags and instalments.

extension _Pickers on _ComposerState {
  Future<int?> _ask(String title, int initial, {String unit = homeCode}) {
    return showCalculator(
      context,
      title: title,
      initial: initial,
      color: _color,
      unit: unit,
    );
  }

  Future<void> _calculate() async {
    final value = await _ask('輸入金額', _f.amount, unit: _f.currency);
    if (value == null) return;
    setState(() {
      _f.setAmount(value);
    });
  }

  Future<void> _pickDate() async {
    final marked = {
      for (final e in _ledger.entriesIn(_f.date.year, _f.date.month)) e.date,
    };
    final day = await _open<DateTime>(
      '日期',
      (done) => DayChoices(
        selected: _f.date,
        latest: _ledger.today,
        today: _ledger.today,
        marked: marked,
        color: _color,
        onPick: done,
      ),
    );
    if (day != null) setState(() => _f.date = day);
  }

  /// An open account; for a refund, one in the purchase's currency.
  Future<String?> _pickAccount(String title, String selected) {
    final refunded = _f.refunded;
    final currency = refunded == null
        ? null
        : _ledger.account(refunded.account).currency;
    return _open<String>(
      title,
      (done) => AccountChoices(
        ledger: _ledger,
        selected: selected,
        currency: currency,
        ring: _color,
        onPick: done,
      ),
    );
  }

  /// A category from them all; 新增 at the end makes one and gives it.
  Future<String?> _pickCategory(String? selected) async {
    final income = _f.tab == ComposeMode.income;
    const adding = '';
    final picked = await _open<String>(
      income ? '收入分類' : '支出分類',
      (done) => OptionGrid<String>(
        options: [
          ...categoryOptions(_ledger, income: income),
          if (!_viewing) const Option(adding, '新增', Glyph.add, Hue.muted),
        ],
        selected: selected,
        ring: _color,
        onPick: done,
      ),
    );
    if (picked != adding) return picked;
    return _newCategory();
  }

  Future<void> _pickHolding() async {
    final picked = await _open<String>(
      '標的',
      (done) => _HoldingChoices(
        ledger: _ledger,
        selected: _f.holding,
        onPick: done,
        onAdd: _viewing ? null : () => done(''),
      ),
    );
    if (picked == null) return;
    if (picked.isEmpty) return _newHolding();
    _set(() => _f.holding = picked);
  }

  Future<void> _newHolding() async {
    final typed = await askText(context, '新增標的代號');
    if (typed == null) return;
    final code = tidyCode(typed);
    if (code.isEmpty) return;
    setState(() => _f.holding = code);
    if (!quotable(code) && mounted) {
      showNote(context, '證交所與櫃買中心沒有「$code」這個代號，市值會以成本估算');
    }
  }

  Future<void> _pickMerchant() async {
    final picked = await _open<String>(
      '商家',
      (done) => _MerchantPicker(
        known: _ledger.merchants,
        initial: _f.merchant,
        onDone: done,
      ),
    );
    if (picked == null) return;
    setState(() => _f.pickMerchant(picked));
  }

  Future<void> _pickTags() async {
    final picked = await _open<List<String>>(
      '標籤',
      (done) => _TagPicker(known: _ledger.tags, initial: _f.tags, onDone: done),
    );
    if (picked != null) setState(() => _f.tags = picked);
  }

  Future<void> _pickInstallments() async {
    final picked = await _open<int>(
      '分期付款',
      (done) => OptionGrid<int>(
        selected: _f.installments,
        columns: 3,
        ring: _color,
        onPick: done,
        options: [
          for (final n in const [0, 3, 6, 12, 24, 30])
            Option(n, n == 0 ? '不分期' : '$n 期', Glyph.card, Hue.muted),
        ],
      ),
    );
    if (picked != null) setState(() => _f.installments = picked);
  }
}
