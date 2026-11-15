part of 'composer.dart';

class _ComposerState extends State<Composer> with WidgetsBindingObserver {
  /// The fields and their rules.
  late final ComposeForm _f = ComposeForm(
    widget.ledger,
    type: widget.type,
    editing: widget.entry,
    draft: widget.draft,
    refunded: widget.refundOf,
  );

  final _note = TextEditingController();
  String? _problem;

  /// An entry opened from a list is shown first; 編輯 unlocks it.
  late var _viewing = widget.entry != null;

  /// The fields have scrolled under the amount: the line between shows.
  var _scrolled = false;

  Ledger get _ledger => widget.ledger;

  /// This ledger's forms put aside, by tab.
  _Drafts get _drafts => _Drafts(_ledger);

  /// The form was put aside as the app went to the background, in case
  /// the phone closes it there; taken back when the app returns.
  var _keptAway = false;

  /// The draft that tab had before, put back when the app returns.
  String? _before;

  /// A choice open in place of the form, if any.
  _Page? _page;

  /// The tallest the fields have stood while closed since the sheet
  /// opened: every tab is made as tall, the amount taking the room to
  /// spare, so the sheet keeps one size from tab to tab. Each opening
  /// starts again, so nothing seen once leaves room behind.
  var _tallest = 0.0;

  /// Waits for the fields to settle before their height counts: a fold
  /// or a split closing shrinks over a few frames, and the frames on the
  /// way down must not count as the form's own height.
  Timer? _settle;

  /// The sums someone paid back is made of, by entry, while 對方還錢.
  Set<String> _paying = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_takeLeftover());
    if (widget.entry == null && widget.draft == null && _f.refunded == null) {
      final draft = _drafts[_f.mode];
      if (draft != null) _takeDraft(draft);
    }
    _note
      ..text = _f.note
      ..addListener(() => _f.note = _note.text);
  }

  /// Fills the form from [draft], and what it paid for others.
  void _takeDraft(_Draft draft) {
    _f.restore(draft.entry, draft.receipt);
    if (draft.lent != null && _f.mode == ComposeMode.expense) {
      _f.lent = draft.lent;
    }
  }

  /// The form as it stands, to put aside.
  _Draft get _asDraft => _Draft(_f.build(), _f.receipt, _f.lent);

  /// Shows the form's note again after the form filled it afresh.
  void _showNote() {
    if (_note.text != _f.note) _note.text = _f.note;
  }

  @override
  void dispose() {
    _settle?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    // Answers a choice still open with none, without building again: the
    // sheet is going away (still mounted until super.dispose).
    final page = _page;
    _page = null;
    page?.close();
    _note.dispose();
    super.dispose();
  }

  /// Starts the current tab afresh.
  void _fresh() {
    _f.fresh();
    _problem = null;
    _showNote();
  }

  /// 代墊 from the expense tab, 對方還錢 from the income tab.
  void _lend({required bool back}) {
    _set(() {
      _f.lend(back: back);
      if (back) _payAll();
    });
    if (_f.people.isEmpty) unawaited(_pickPerson());
  }

  /// Back from 代墊 or 對方還錢 to a plain entry of the same tab.
  void _unlend() => _set(() {
    _f.mode = _f.tab;
    _paying = {};
  });

  /// Everything the person owes is being paid back: each sum ticked and
  /// the amount all they owe.
  void _payAll() {
    if (_f.to.isEmpty) return;
    _paying = {for (final (e, _) in _ledger.owedBy(_f.to)) e.id};
    final owed = _ledger.balance(_f.to);
    if (owed > 0) _f.setAmount(owed);
  }

  /// One sum ticked or not among what is being paid back; the amount
  /// follows.
  void _togglePaying(String id) => _set(() {
    _paying = {..._paying};
    if (!_paying.remove(id)) _paying.add(id);
    // All they owe but the sums not ticked, which stay owed.
    final kept = _ledger
        .owedBy(_f.to)
        .fold(0, (sum, o) => _paying.contains(o.$1.id) ? sum : sum + o.$2);
    _f.setAmount(math.max(0, _ledger.balance(_f.to) - kept));
  });

  /// Opens a choice inside the sheet in place of the form, titled
  /// [title]; [build] is given what to call with the value chosen. The
  /// arrow back or the phone's back returns to the form with none.
  Future<T?> _open<T>(
    String title,
    Widget Function(ValueChanged<T> done) build,
  ) {
    _page?.close();
    final result = Completer<T?>();
    late final _Page page;
    void finish(T? value) {
      if (result.isCompleted) return;
      result.complete(value);
      if (identical(_page, page)) _set(() => _page = null);
    }

    page = _Page(title, build(finish), () => finish(null));
    _set(() => _page = page);
    return result.future;
  }

  /// A category picked: back to a plain expense or income from 代墊.
  void _pickCategoryName(String name) => _set(() => _f.pickCategory(name));

  /// Moves to another tab: the fields start afresh, or as that tab's
  /// draft left them. A receipt photo already chosen stays, unless the
  /// draft brings its own: the photo is of what was bought or paid,
  /// whichever kind of entry it turns out to be.
  void _switch(ComposeMode mode) {
    if (mode == _f.mode) return;
    setState(() {
      _f.switchTo(mode);
      final draft = _drafts[mode];
      if (draft != null && widget.entry == null) {
        final photo = _f.receipt;
        _takeDraft(draft);
        _f.receipt ??= photo;
      }
      _problem = null;
      _showNote();
    });
  }

  Color get _color {
    if (_f.refunded != null) return Hue.positive;
    return _f.tab.color;
  }

  /// What the tabs do not say: an entry being changed, money paid for
  /// someone or paid back, a refund. Shown as small tags under the top
  /// row; a new plain entry needs none.
  List<(String, Color)> get _marks => [
    if (_f.refunded != null) ('退款', Hue.positive),
    if (widget.entry != null && !_viewing) ('編輯中', Hue.accent),
  ];

  String get _action {
    if (widget.entry != null) return '儲存修改';
    if (_f.refunded != null) return '記下退款';
    if (_f.lending && _f.own <= 0) return '記下代墊';
    return switch (_f.type) {
      EntryType.expense => '記下支出',
      EntryType.income => '記下收入',
      EntryType.transfer when _f.mode == ComposeMode.lend =>
        _f.back ? '記下還款' : '記下代墊',
      EntryType.transfer => '確認轉帳',
      EntryType.buy => '記下買進',
      EntryType.sell => '記下賣出',
      EntryType.dividend => '記下股息',
    };
  }

  Future<String?> _newCategory() async {
    final income = _f.tab == ComposeMode.income;
    final count = _ledger.categories.length;
    final made = await showCategoryEditor(
      context,
      title: income ? '新增收入分類' : '新增支出分類',
      initial: Category(
        '',
        income ? 'income' : 'other',
        Hue.categoryColors[count % Hue.categoryColors.length].toARGB32(),
        income: income,
      ),
      colors: Hue.categoryColors,
      ledger: _ledger,
    );
    if (made == null) return null;
    _ledger.addCategory(made);
    return made.name;
  }

  void _split() => setState(_f.toggleSplit);

  void _evenly() => setState(_f.evenly);

  /// A category from the whole list while splitting: added as a part,
  /// unless it is one already.
  Future<void> _addPart() async {
    final name = await _pickCategory(null);
    if (name == null) return;
    final parts = _f.parts ?? const [];
    if (parts.any((p) => p.$1 == name)) return;
    setState(() => _f.addPart(name));
  }

  Future<void> _editPart(int index) async {
    final parts = _f.parts;
    if (parts == null) return;
    final (name, value) = parts[index];
    final amount = await _ask(name, value);
    if (amount == null) return;
    setState(() => _f.setPart(index, amount));
  }

  void _changeTrade(EntryType trade) => setState(() => _f.changeTrade(trade));

  /// A receipt photo the camera took while the phone closed the app goes
  /// with the next new entry.
  Future<void> _takeLeftover() async {
    final photos = widget.photos;
    if (photos == null || widget.entry != null || _f.refunded != null) return;
    final String? name;
    try {
      name = await photos.takeLeftover();
    } on Object {
      return;
    }
    if (name == null || !mounted) return;
    setState(() => _f.receipt = name);
  }

  /// A new entry written part way is kept as the app leaves, so a phone
  /// short of memory closing the app loses nothing: it is there, with
  /// its photo, the next time 記一筆 opens. Back in time, it is taken
  /// away again, unless it was put aside with 暫存 before.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (widget.entry != null || _viewing || _f.refunded != null) return;
    switch (state) {
      case AppLifecycleState.paused || AppLifecycleState.hidden:
        if (_keptAway || (_f.amount == 0 && _f.receipt == null)) return;
        try {
          final draft = _asDraft;
          _before = _ledger.draft(_f.tab.name);
          _drafts[_f.tab] = draft;
          _keptAway = true;
        } on Object {
          // A form that cannot be built yet is not worth keeping.
        }
      case AppLifecycleState.resumed:
        if (!_keptAway) return;
        _keptAway = false;
        _ledger.setDraft(_f.tab.name, _before);
      default:
        break;
    }
  }

  void _submit() {
    final problem = _f.problem;
    if (problem != null) {
      setState(() => _problem = problem);
      return;
    }
    // Paid partly for others, more than one entry, written as one.
    final made = _f.buildAll();
    final entry = made.first;
    try {
      if (widget.entry != null) {
        _ledger.replaceGroup(
          made,
          _f.openedIds,
          receipt: _f.receipt,
          receiptOn: entry.id,
        );
      } else if (made.length == 1) {
        _ledger.add(entry, receipt: _f.receipt);
      } else {
        _ledger.addAll(made);
        final photo = _f.receipt;
        if (photo != null) _ledger.setReceipt(entry.id, photo);
      }
    } on StateError catch (error) {
      setState(() => _problem = error.message);
      return;
    }
    _drafts.remove(_f.tab);
    Navigator.of(context).pop((ComposeOutcome.saved, entry));
  }

  void _putAside() {
    _keptAway = false;
    _drafts[_f.tab] = _asDraft;
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final entry = widget.entry;
    if (entry == null) return;
    final ok = await confirm(context, '刪除這一筆？', '刪除', danger: true);
    if (ok && mounted) {
      Navigator.of(context).pop((ComposeOutcome.deleted, entry));
    }
  }

  /// The fields' own height, kept when it is the tallest yet; only while
  /// the form shows closed, so an opened fold, a split or a problem does
  /// not make every tab taller, and stay so after it is closed again.
  void _measured(double height) {
    _settle?.cancel();
    _settle = Timer(const Duration(milliseconds: 400), () {
      if (!mounted || _page != null || _f.more || _problem != null) return;
      if (_f.parts != null) return;
      if (height > _tallest + 0.5) setState(() => _tallest = height);
    });
  }

  @override
  Widget build(BuildContext context) {
    final page = _page;
    if (page != null) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) page.close();
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: _PageHeader(title: page.title, onBack: page.close),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: page.body,
              ),
            ),
          ],
        ),
      );
    }
    final problem = _problem;
    final entry = widget.entry;
    final refunded = _f.refunded;
    final canRefund =
        _viewing &&
        entry != null &&
        entry.type == EntryType.expense &&
        _ledger.refundable(entry) > 0;
    // The top stays put: the kind of entry, or what is being changed.
    final top = Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (refunded != null)
            Padding(
              padding: const EdgeInsets.only(right: 8, bottom: 4),
              child: _OriginalTile(ledger: _ledger, entry: refunded),
            )
          else if (_viewing)
            Center(child: Pill(_f.mode.label, color: _f.mode.color))
          else if (entry == null)
            _Tabs(
              labels: [for (final m in ComposeForm.tabs) m.label],
              selected: ComposeForm.tabs.indexOf(_f.tab),
              color: _f.tab.color,
              onChanged: (i) => _switch(ComposeForm.tabs[i]),
              onReset: () => setState(() {
                _drafts.remove(_f.tab);
                _f.mode = _f.tab;
                _fresh();
              }),
            ),
          if (_marks.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4, right: 8),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 6,
                children: [
                  for (final (label, color) in _marks)
                    Pill(label, color: color),
                ],
              ),
            ),
        ],
      ),
    );
    // The amount stays under the top with it; the fields under it scroll,
    // cut off at the amount's foot, where a thin line shows once they
    // have moved.
    final all = _fields();
    final hero = all.isNotEmpty && all.first is _AmountHero
        ? all.first as _AmountHero
        : null;
    final below = [
      if (hero?.under case final under?) ...[const SizedBox(height: 4), under],
      ...hero == null ? all : all.skip(1),
      if (problem != null)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(
            problem,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Hue.danger),
          ),
        ),
    ];
    final pinned = hero == null
        ? null
        : Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: IgnorePointer(
              ignoring: _viewing,
              child: _AmountHero(
                label: hero.label,
                unit: hero.unit,
                value: hero.value,
                color: hero.color,
                onTap: hero.onTap,
                sub: hero.sub,
              ),
            ),
          );
    // The sheet is as tall as the tallest tab's fields, which scroll
    // inside it past three quarters of the screen.
    final fields = NotificationListener<ScrollNotification>(
      onNotification: (n) {
        final moved = n.metrics.pixels > 0.5;
        if (moved != _scrolled) setState(() => _scrolled = moved);
        return false;
      },
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
        child: IgnorePointer(
          ignoring: _viewing,
          child: _Fill(
            // A new entry keeps the tallest tab's height, so switching
            // tabs does not jump; one looked at or edited takes only
            // the room it needs.
            minHeight: widget.entry == null ? _tallest : 0,
            grow: -1,
            onHeight: _measured,
            children: below,
          ),
        ),
      ),
    );
    // 刪除 or 暫存 and the main button stay at the foot of the sheet, in
    // reach however long the form is.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        top,
        ?pinned,
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 1,
          margin: const EdgeInsets.only(top: 8),
          color: _scrolled ? Hue.line : Hue.line.withValues(alpha: 0),
        ),
        Flexible(child: ClipRect(child: fields)),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 20, 16),
          child: Row(
            children: [
              TextButton(
                key: Keys.discard,
                onPressed: entry != null ? _delete : _putAside,
                style: wordButton(
                  entry != null ? Hue.danger : Hue.muted,
                  minimumSize: Size(64, 48),
                ),
                child: Text(entry != null ? '刪除' : '暫存'),
              ),
              if (canRefund)
                TextButton(
                  onPressed: () =>
                      Navigator.of(context).pop((ComposeOutcome.refund, entry)),
                  style: wordButton(Hue.positive, minimumSize: Size(64, 48)),
                  child: const Text('退款'),
                ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 54,
                  child: FilledButton(
                    onPressed: _viewing
                        ? () => setState(() => _viewing = false)
                        : _submit,
                    key: Keys.save,
                    style: solidButton(
                      _viewing ? Hue.accent : _color,
                      radius: 18,
                      words: appFont.copyWith(
                        fontSize: TextSize.title,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    child: Text(_viewing ? '編輯' : _action),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Applies [change] while the form is still on screen: the field
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
        showNote(context, '這不是電子發票左邊的 QR Code，請掃左邊那個');
        return;
      }
      if (invoiceRecorded(_ledger, invoice.date, invoice.number)) {
        showNote(context, '發票 ${invoice.number} 已經記過了');
        return;
      }
      if (invoice.wantsMore) {
        showNote(context, '還有品項在右邊的 QR Code，請再掃一次');
        final right = await scan();
        if (right != null) invoice = invoice.withRight(right);
      }
      if (!mounted) return;
      final scanned = invoice;
      _set(() => _f.fillInvoice(scanned));
    } on Object catch (error) {
      if (mounted) showNote(context, '沒有掃到：$error');
    }
  }

  void _set(VoidCallback change) {
    if (mounted) setState(change);
  }
}
