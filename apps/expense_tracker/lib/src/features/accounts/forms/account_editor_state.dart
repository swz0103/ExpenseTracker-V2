part of 'account_editor.dart';

class _AccountEditorState extends State<_AccountEditor> {
  late final _old = widget.account;

  /// The fields and what saving does.
  late final _f = AccountForm(widget.ledger, old: _old)
    ..kind = _old?.kind ?? widget.kind ?? AccountKind.bank;

  /// The fields as the form opened, to ask before leaving changes (D83).
  late final List<Object?> _opened;

  @override
  void initState() {
    super.initState();
    _opened = _f.fields;
  }

  late final TextEditingController _principal = TextEditingController(
    text: _f.principal,
  )..addListener(() => setState(() => _f.principal = _principal.text));

  /// A loan's form: no kinds, marks or currencies, but what was borrowed
  /// and, for a new one, where the money went.
  bool get _loanForm => _f.kind == AccountKind.loan;
  // The card on top shows what is typed as it is typed.
  late final TextEditingController _name = TextEditingController(text: _f.name)
    ..addListener(
      () => setState(() {
        _f.name = _name.text;
        _problem = null;
      }),
    );

  /// Why 儲存 did nothing, said above it.
  String? _problem;
  late final TextEditingController _balance = TextEditingController(
    text: _f.balance,
  )..addListener(() => setState(() => _f.balance = _balance.text));
  late final TextEditingController _limit = TextEditingController(
    text: _f.limit,
  )..addListener(() => setState(() => _f.limit = _limit.text));

  late final TextEditingController _discount = TextEditingController(
    text: _f.discount,
  )..addListener(() => setState(() => _f.discount = _discount.text));

  late final TextEditingController _rate = TextEditingController(text: _f.rate)
    ..addListener(() => setState(() => _f.rate = _rate.text));
  late final TextEditingController _months = TextEditingController(
    text: _f.months,
  )..addListener(() => setState(() => _f.months = _months.text));

  /// The currencies offered in the row; the rest open from 更多.
  static const _common = [homeCode, 'USD', 'JPY', 'EUR', 'CNY'];

  /// Lets the loan's fields in the part file set state.
  void _set(VoidCallback change) => setState(change);

  @override
  void dispose() {
    _name.dispose();
    _balance.dispose();
    _principal.dispose();
    _limit.dispose();
    _discount.dispose();
    _rate.dispose();
    _months.dispose();
    super.dispose();
  }

  void _save() {
    final problem = _f.problem;
    if (problem != null) {
      setState(() => _problem = problem);
      return;
    }
    if (_f.save()) EditGuard.close(context);
  }

  /// Archives the account, or brings it back, told with 復原 (D82). One
  /// with money left is settled first: its balance moves to the account
  /// picked, and 復原 takes that back too.
  Future<void> _archive() async {
    final old = _old;
    if (old == null) return;
    final ledger = widget.ledger;
    final left = ledger.balanceService.finalBalance(old.id);
    Entry? settlement;
    if (!old.archived && left != 0) {
      final into = await pickOption<String>(
        context,
        title: left > 0 ? '餘額轉到哪個帳戶' : '由哪個帳戶結清欠款',
        selected: null,
        columns: 3,
        options: accountOptions(
          ledger,
          currency: old.currency,
          where: (a) => a.id != old.id && !a.kind.isDebt,
        ),
      );
      if (into == null || !mounted) return;
      final made = AccountForm.settlement(ledger, old, into);
      if (!refusalShown(context, () => ledger.entryCommands.add(made))) return;
      // The entry as the book holds it, the one its undo takes back.
      settlement = ledger.entries.byId(made.id);
    }
    final undo = ledger.accountCommands.setArchived(
      old.id,
      archived: !old.archived,
    );
    if (!mounted) return;
    if (undo != null) {
      showUndo(
        context,
        old.archived
            ? DoneWords.unarchived(old.name)
            : DoneWords.archived(old.name),
        () {
          undo();
          if (settlement != null) {
            ledger.entryCommands.takeBack([settlement]);
          }
        },
      );
    }
    EditGuard.close(context, !old.archived);
  }

  /// Deletes the account. Nothing in the trash naming it: not asked
  /// first, told with 復原 (D82). Deleted entries in the trash that name
  /// it go for good with it, which cannot be undone: asked first (D78).
  Future<void> _remove() async {
    final old = _old;
    if (old == null) return;
    final ledger = widget.ledger;
    final commands = ledger.accountCommands;
    final trashed = commands.trashedNaming(old.id);
    if (trashed.isNotEmpty) {
      final ok = await confirm(
        context,
        '刪除「${old.name}」？',
        Words.delete,
        danger: true,
        body: trashedNamingNote(trashed.length),
      );
      if (!ok || !mounted) return;
      ledger.entryCommands.discardTrashed(trashed);
    }
    final undo = commands.removeAccount(old.id);
    if (undo != null) {
      if (trashed.isEmpty) {
        showUndo(context, DoneWords.deleted(old.name), undo);
      } else {
        showNote(context, DoneWords.deleted(old.name));
      }
    }
    EditGuard.close(context, true);
  }

  Future<void> _pickDay(bool closing) async {
    final picked = await showSheet<int>(
      context,
      (context) => Padding(
        padding: const EdgeInsets.fromLTRB(Space.s4, 0, Space.s4, Space.s5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              closing ? '結帳日' : '繳款日',
              style: const TextStyle(
                fontSize: TextSize.title,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: Space.s3),
            GridView.count(
              crossAxisCount: 7,
              shrinkWrap: true,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              children: [
                for (var day = 1; day <= 28; day++)
                  _DayKey(
                    day: day,
                    picked: day == (closing ? _f.closing : _f.due),
                    onTap: () => Navigator.of(context).pop(day),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    setState(() {
      if (closing) {
        _f.closing = picked;
      } else {
        _f.due = picked;
      }
    });
  }

  /// The kinds the form offers: those of 我的帳戶, and the account's own
  /// when it is of another.
  List<AccountKind> get _kinds {
    final old = _old;
    return [
      ...walletKinds,
      if (old != null && !walletKinds.contains(old.kind)) old.kind,
    ];
  }

  /// The six marks shown for the kind, with the account's own in the
  /// last place when it is not one of them.
  List<String> get _usual {
    final usual = usualAccountIcons(_f.kind);
    final own = _f.icon;
    if (usual.isEmpty) return own == null ? const [] : [own];
    if (own == null || usual.contains(own)) return usual;
    return [...usual.take(usual.length - 1), own];
  }

  /// A centre panel of colours: the kind's own first, then the others.
  Future<void> _pickColor() async {
    final picked = await showPanel<int>(
      context,
      (context) => CenterPanel(
        glyph: Glyph.sparkle,
        color: accountColor(_preview),
        title: '卡片顏色',
        // 48 dp to tap each, 56 apart as the 44 dp dots were.
        body: Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            SwatchButton(
              color: accountKindColor(_f.kind),
              label: '預設',
              selected: _f.color == null,
              onTap: () => Navigator.of(context).pop(-1),
            ),
            for (final c in AppColors.categoryColors)
              SwatchButton(
                color: shownColor(c),
                selected: _f.color == c.toARGB32(),
                onTap: () => Navigator.of(context).pop(c.toARGB32()),
              ),
          ],
        ),
        actions: [
          PanelButton(Words.cancel, onTap: () => Navigator.of(context).pop()),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _f.color = picked == -1 ? null : picked);
  }

  /// Every currency in a panel, for those not in the row.
  Future<void> _moreCurrencies() async {
    final picked = await pickOption<String>(
      context,
      title: '幣別',
      selected: _f.currency,
      options: [
        for (final code in Currency.supported)
          Option(code, code, Glyph.exchange, accountColor(_preview)),
      ],
    );
    if (picked != null && mounted) setState(() => _f.currency = picked);
  }

  Future<void> _moreIcons() async {
    final color = accountColor(_preview);
    final shown = _f.icon ?? kindIcon(_f.kind).name;
    final picked = await showSheet<String>(
      context,
      (context) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Space.s4, 0, Space.s4, Space.s5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '選圖示',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: TextSize.title,
                fontWeight: FontWeight.w700,
              ),
            ),
            for (final (group, marks) in accountIconGroups) ...[
              Padding(
                padding: const EdgeInsets.only(top: Space.s4, bottom: Space.s2),
                child: Text(group, style: accentLabel),
              ),
              // Each row as tall as its words: with large text a name
              // no longer spills out of a cell of fixed height.
              CardGrid(columns: 4, gap: 0, [
                for (final (key, name) in marks)
                  TapArea(
                    label: name,
                    selected: key == shown,
                    onTap: () => Navigator.of(context).pop(key),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: Space.s2),
                      child: Column(
                        children: [
                          IconChoiceSquare(
                            icon: iconFor(key),
                            color: color,
                            selected: key == shown,
                          ),
                          const SizedBox(height: Space.s1),
                          Text(
                            name,
                            textAlign: TextAlign.center,
                            style: mutedTiny,
                          ),
                        ],
                      ),
                    ),
                  ),
              ]),
            ],
          ],
        ),
      ),
    );
    if (picked != null && mounted) setState(() => _f.icon = picked);
  }

  Future<void> _pickFund() async {
    final ledger = widget.ledger;
    final picked = await pickOption<String>(
      context,
      title: '撥款到',
      selected: _f.fundInto ?? '',
      columns: 3,
      options: [
        const Option('', '不入帳', Glyph.loan, AppColors.investment),
        ...accountOptions(
          ledger,
          currency: homeCode,
          where: (a) => !a.kind.isDebt && a.kind != AccountKind.receivable,
        ),
      ],
    );
    if (picked == null || !mounted) return;
    setState(() => _f.fundInto = picked.isEmpty ? null : picked);
  }

  /// 算進負債與淨資產, or 計入資產與淨資產, as a whole row.
  Widget get _counted {
    final label = _loanForm ? '算進負債與淨資產' : '計入資產與淨資產';
    return FormGroup(
      child: ToggleRow(
        value: _f.counted,
        onChanged: (on) => setState(() => _f.counted = on),
        label: label,
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontSize: TextSize.body),
              ),
            ),
            TickSwitch(
              value: _f.counted,
              label: label,
              onChanged: (on) => setState(() => _f.counted = on),
            ),
          ],
        ),
      ),
    );
  }

  /// 圖示: the marks most used for its kind, and 更多 for every one.
  Widget _iconGroup(Color color) {
    final shownIcon = _f.icon ?? kindIcon(_f.kind).name;
    return FormGroup(
      title: '圖示',
      child: Row(
        children: [
          for (final key in _usual)
            Expanded(
              child: IconChoiceButton(
                icon: accountMark(key) ?? kindIcon(_f.kind),
                label: '圖示：${accountIconName(key)}',
                color: color,
                selected: key == shownIcon,
                size: 40,
                background: AppColors.white,
                onTap: () => setState(() => _f.icon = key),
              ),
            ),
          Expanded(
            child: TapArea(
              label: '更多圖示',
              onTap: _moreIcons,
              child: Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(Radii.medium),
                ),
                padding: const EdgeInsets.all(Space.half),
                // As large as the phone's text, until the square beside the
                // icons is full.
                child: const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '更多',
                    style: TextStyle(
                      fontSize: TextSize.caption,
                      fontWeight: FontWeight.w700,
                      color: AppColors.muted,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 類型: the kinds of 我的帳戶 as pills.
  Widget _kindGroup() {
    return FormGroup(
      title: '類型',
      child: Row(
        children: [
          for (final (i, kind) in _kinds.indexed) ...[
            if (i > 0) const SizedBox(width: Space.s2),
            Expanded(
              child: ChoicePill(
                label: switch (kind) {
                  AccountKind.bank => '銀行',
                  AccountKind.wallet => '支付',
                  _ => groupName(kind),
                },
                selected: kind == _f.kind,
                background: AppColors.white,
                onTap: () => setState(() => _f.kind = kind),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 幣別: the usual currencies, and 更多 for every one.
  Widget _currencyGroup() {
    return FormGroup(
      title: '幣別',
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final code in [
              ..._common,
              if (!_common.contains(_f.currency)) _f.currency,
            ]) ...[
              ChoicePill(
                label: code == homeCode ? '新台幣' : code,
                selected: code == _f.currency,
                background: AppColors.white,
                onTap: () => setState(() => _f.currency = code),
              ),
              const SizedBox(width: Space.s2),
            ],
            ChoicePill(
              label: '更多',
              selected: false,
              background: AppColors.white,
              onTap: _moreCurrencies,
            ),
          ],
        ),
      ),
    );
  }

  /// 結帳日 and 繳款日 of a credit card, side by side.
  Widget _cardDays() {
    return CardRow([
      FigureCard(
        color: AppColors.card,
        icon: Glyph.calendar,
        label: '結帳日',
        value: '每月 ${_f.closing} 日',
        size: TextSize.body,
        onTap: () => _pickDay(true),
      ),
      FigureCard(
        color: AppColors.card,
        icon: Glyph.calendar,
        label: '繳款日',
        value: '每月 ${_f.due} 日',
        size: TextSize.body,
        onTap: () => _pickDay(false),
      ),
    ]);
  }

  /// The fields of an account other than a loan, top to bottom.
  List<Widget> _accountFields(Account? old, Color color) {
    return [
      Text(
        old == null ? '新增帳戶' : '編輯帳戶',
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: TextSize.heading,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: Space.s3),
      _EditCard(
        color: color,
        icon: accountIcon(_preview),
        kind: cardKindLabel(_preview),
        name: _name,
        balance: _balance,
        balanceLabel: _f.kind.isDebt ? '目前欠款' : '目前餘額',
        onColor: _pickColor,
      ),
      _kindGroup(),
      _iconGroup(color),
      if (old == null && _f.foreignAllowed) _currencyGroup(),
      if (_f.kind == AccountKind.card) _cardDays(),
      if (_f.kind == AccountKind.card)
        FormGroup(
          title: '信用額度',
          child: _Field(
            controller: _limit,
            hint: '額度',
            number: true,
            error: _f.limitProblem,
          ),
        ),
      if (_f.trades) _discountGroup(),
      _counted,
      _buttons(old),
      if (old != null)
        Padding(
          padding: const EdgeInsets.only(top: Space.s2),
          child: Text(
            '目前 ${widget.ledger.moneyIn(widget.ledger.balanceService.balance(old.id), old.currency)}',
            textAlign: TextAlign.center,
            style: mutedSmall,
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final old = _old;
    final color = accountColor(_preview);
    return EditGuard(
      changed: !listEquals(_f.fields, _opened),
      child: SingleChildScrollView(
        physics: const FitScrollPhysics(16),
        padding: const EdgeInsets.fromLTRB(Space.s4, 0, Space.s4, Space.s4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: _loanForm ? _loanFields(old) : _accountFields(old, color),
        ),
      ),
    );
  }
}
