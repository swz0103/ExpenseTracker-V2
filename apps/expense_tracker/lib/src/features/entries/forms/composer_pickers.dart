part of 'composer.dart';

// The choices the form opens: amount, day, account, category, holding,
// merchant, tags and instalments; and what it takes in from outside, an
// invoice scanned and a receipt photo left over.

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
    _set(() {
      _f.setAmount(value);
    });
  }

  Future<void> _pickDate() async {
    final marked = {
      for (final e in _ledger.entries.inMonth(_f.date.year, _f.date.month))
        e.date,
    };
    final day = await _open<DateTime>(
      Words.date,
      (done) => DayChoices(
        selected: _f.date,
        latest: _ledger.today,
        today: _ledger.today,
        marked: marked,
        color: _color,
        onPick: done,
      ),
    );
    if (day != null) _set(() => _f.date = day);
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
          if (!_viewing)
            const Option(adding, Words.add, Glyph.add, AppColors.muted),
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
      (done) => HoldingChoices(
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
    _set(() => _f.holding = code);
    if (!quotable(code) && mounted) {
      showNote(context, '證交所與櫃買中心沒有「$code」這個代號，市值會以成本估算');
    }
  }

  Future<void> _pickMerchant() async {
    final picked = await _open<String>(
      Words.merchant,
      (done) => MerchantPicker(
        known: _ledger.entryQueryService.merchants,
        initial: _f.merchant,
        onDone: done,
      ),
    );
    if (picked == null) return;
    _set(() => _f.pickMerchant(picked));
  }

  Future<void> _pickTags() async {
    final picked = await _open<List<String>>(
      Words.tag,
      (done) => TagPicker(
        known: _ledger.reportService.tags,
        initial: _f.tags,
        onDone: done,
      ),
    );
    if (picked != null) _set(() => _f.tags = picked);
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
            Option(
              n,
              n == 0 ? '不分期' : countOf(n, CountUnit.periods),
              Glyph.card,
              AppColors.muted,
            ),
        ],
      ),
    );
    if (picked != null) _set(() => _f.installments = picked);
  }

  /// A receipt photo the camera took while the phone closed the app goes
  /// with the next new entry.
  Future<void> _takeLeftover() async {
    final photos = widget.photos;
    if (photos == null || widget.entry != null || _f.refunded != null) return;
    final String? name;
    try {
      name = await photos.takeLeftover();
    } on Object catch (error) {
      ErrorLog.instance.record('收據照片', error);
      return;
    }
    if (name == null || !mounted) return;
    _set(() => _f.receipt = name);
  }

  /// Applies `change` while the form is still on screen: the field
  /// builders in composer_fields.dart run it after a dialog closes.
  /// 掃發票: reads a paper e-invoice's left QR code (and its right one when
  /// the items go on there) and fills the form: the day, the total, its
  /// items and number in the note, tagged 發票, and a category guessed from
  /// the items. One already in the book is said, not filled again.
  Future<void> _scanInvoice() async {
    final scan = widget.scan;
    if (scan == null) return;
    try {
      final left = await scan();
      if (left == null || !mounted) return;
      var invoice = InvoiceQr.parse(left);
      if (invoice == null) {
        _say('這不是電子發票左邊的 QR Code，請掃左邊那個');
        return;
      }
      if (invoiceRecorded(_ledger.entries, invoice.date, invoice.number)) {
        _say('發票 ${invoice.number} 已經記過了');
        return;
      }
      if (invoice.wantsMore) {
        _say('還有品項在右邊的 QR Code，請再掃一次');
        final right = await scan();
        if (right != null) invoice = invoice.withRight(right);
      }
      if (!mounted) return;
      final scanned = invoice;
      _set(() => _f.fillInvoice(scanned));
    } on Object catch (error) {
      // Exception to error words: the scanner says what went wrong in
      // words meant for the person (androidScanQr).
      _say('$error');
    }
  }
}
