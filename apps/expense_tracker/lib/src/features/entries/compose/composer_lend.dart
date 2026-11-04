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
    final owed = person == null ? 0 : _ledger.balance(person.id);
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
        under: _PersonPill(
          text: _f.back ? '$name 還錢' : '幫 $name 付',
          sub: sub,
          color: _color,
          onTap: _pickPerson,
          onClear: _viewing || widget.entry != null ? null : _unlend,
        ),
      ),
      if (_f.back) _owedCards() else _categories(true),
      _pair(_accountPick(_f.back ? '收款帳戶' : '付款帳戶'), _datePick()),
      _extras(false),
    ];
  }

  /// What the person still owes, sum by sum, as cards to tick in a row.
  Widget _owedCards() {
    final owed = _f.to.isEmpty ? const <(Entry, int)>[] : _ledger.owedBy(_f.to);
    if (owed.isEmpty || _viewing) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final (i, (e, left)) in owed.indexed) ...[
              if (i > 0) const SizedBox(width: 8),
              _OwedCard(
                title: e.note.isNotEmpty
                    ? e.note
                    : e.merchant.isNotEmpty
                    ? e.merchant
                    : '代墊',
                when: '${e.date.month}/${e.date.day}',
                amount: groupDigits(left),
                picked: _paying.contains(e.id),
                color: _color,
                onTap: () => _togglePaying(e.id),
              ),
            ],
          ],
        ),
      ),
    );
  }

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
        if (_f.back) _payAll();
      });
      return;
    }
    final name = await askText(context, '代墊對象的名字');
    if (name == null || name.trim().isEmpty || !mounted) return;
    final account = Account(
      _ledger.newId(),
      name.trim(),
      AccountKind.receivable,
      0,
    );
    _ledger.addAccount(account);
    _set(() {
      _f.to = account.id;
      _paying = {};
    });
  }
}
