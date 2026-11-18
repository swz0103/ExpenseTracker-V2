part of 'composer.dart';

/// The 代墊 fields: whom the money is for or from, and the person's own
/// account that keeps what they owe.
extension _LendFields on _ComposerState {
  /// 代墊 under 支出 (paid for someone) or 對方還錢 under 收入. Each
  /// person has an account of their own that keeps what they owe. Paid
  /// back, the sums they owe stand in place of the categories, to tick
  /// those being paid.
  List<Widget> _lendFields() {
    final person = _f.to.isEmpty ? null : _ledger.account(_f.to);
    final owed = _f.owedNow;
    final name = person?.name ?? '新增對象';
    final String sub;
    if (person == null) {
      sub = '';
    } else if (_f.back) {
      final left = owed - _f.amount;
      sub = left <= 0 ? '· 還完不欠' : '· 還完欠 ${_ledger.money(left)}';
    } else {
      sub = owed == 0 ? '· 目前沒有欠' : '· 目前欠 ${_ledger.money(owed)}';
    }
    return [
      _hero(
        under: PersonPill(
          text: _f.back ? '$name 還錢' : '幫 $name 付',
          sub: sub,
          color: _color,
          onTap: _pickPerson,
          onClear: _viewing || widget.entry != null ? null : _unlend,
        ),
      ),
      if (_f.back) _owedCards() else _categories(true),
      _pair(_accountPick(_f.back ? '收款帳戶' : '付款帳戶'), _datePick()),
      ExtrasFields(this).build(expense: false),
    ];
  }

  /// Under the amount of a spending paid partly for others, in place of
  /// 常用: one's own share, then each person's, a tap to change it, ＋ for
  /// more people and a cross back to one's own spending.
  Widget _lendRow() {
    final shares = _f.lent ?? const <(String, int)>[];
    return UsualRow(
      lead: UsualChip(
        icon: Glyph.wallet,
        name: '自己',
        amount: groupDigits(_f.own),
        onTap: _calculate,
      ),
      [
        for (final (i, (person, value)) in shares.indexed)
          LentShareChip(
            name: _ledger.account(person).name,
            amount: groupDigits(value),
            color: Hue.receivable,
            onTap: _viewing
                ? null
                : () async {
                    final name = _ledger.account(person).name;
                    final typed = await _ask('幫$name付', value);
                    if (typed != null) _set(() => _f.setLent(i, typed));
                  },
          ),
        if (!_viewing) ...[
          UsualChip(icon: Glyph.add, name: '代墊給…', onTap: _pickLent),
          IconButton(
            tooltip: '不代墊',
            onPressed: () => _set(_f.stopLending),
            icon: const GlyphIcon(Glyph.close, size: 16, color: Hue.faint),
          ),
        ],
      ],
    );
  }

  /// Picks whom a spending is paid for, any number of people, or adds a
  /// new person; the amount is then shared evenly.
  Future<void> _pickLent() async {
    final picked = await _open<List<String>>(
      '代墊給誰',
      (done) => PeopleChoices(
        people: _f.people,
        selected: [for (final (p, _) in _f.lent ?? const <(String, int)>[]) p],
        color: _color,
        onDone: done,
        onAdd: _addPerson,
      ),
    );
    if (picked == null || !mounted) return;
    _set(() => _f.lendTo(picked));
  }

  /// Asks for a new person's name and opens an account for what they owe.
  Future<Account?> _addPerson() async {
    final name = await askText(context, '代墊對象的名字');
    if (name == null || !mounted) return null;
    return _f.addPerson(name);
  }

  /// What the person still owes, sum by sum, as cards to tick in a row;
  /// nothing while only looked at.
  Widget _owedCards() => _viewing
      ? const SizedBox.shrink()
      : OwedCardRow(
          sums: _f.owedSums,
          titleOf: _f.owedTitle,
          paying: _f.paying,
          color: _color,
          onToggle: _togglePaying,
        );

  /// Picks whom the money is for, or adds a new person.
  Future<void> _pickPerson() async {
    const adding = '';
    final picked = _f.people.isEmpty
        ? adding
        : await _open<String>(
            _f.back ? '誰還錢' : '幫誰付',
            (done) => OptionGrid<String>(
              selected: _f.to,
              columns: 3,
              ring: _color,
              onPick: done,
              options: [
                for (final a in _f.people)
                  Option(a.id, a.name, Glyph.heart, Hue.muted),
                const Option(adding, '新增對象', Glyph.add, Hue.muted),
              ],
            ),
          );
    if (picked == null || !mounted) return;
    if (picked != adding) {
      _set(() {
        _f.to = picked;
        if (_f.back) _f.payAll();
      });
      return;
    }
    final account = await _addPerson();
    if (account == null) return;
    _set(() {
      _f.to = account.id;
      _f.paying = {};
    });
  }
}
