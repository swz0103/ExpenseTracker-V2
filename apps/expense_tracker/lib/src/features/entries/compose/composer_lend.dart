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

  /// Under the amount of a spending paid partly for others, in place of
  /// 常用: one's own share, then each person's, a tap to change it, ＋ for
  /// more people and a cross back to one's own spending.
  Widget _lendRow() {
    final shares = _f.lent ?? const <(String, int)>[];
    return _UsualRow(
      lead: _UsualChip(
        icon: Glyph.wallet,
        name: '自己',
        amount: groupDigits(_f.own),
        onTap: _calculate,
      ),
      [
        for (final (i, (person, value)) in shares.indexed)
          _LentChip(
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
          _UsualChip(icon: Glyph.add, name: '代墊給…', onTap: _pickLent),
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
      (done) => _PeopleChoices(
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
    if (name == null || name.trim().isEmpty || !mounted) return null;
    final account = Account(
      _ledger.newId(),
      name.trim(),
      AccountKind.receivable,
      0,
    );
    _ledger.addAccount(account);
    return account;
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
                title: _owedTitle(e),
                when: e.group == null
                    ? '${e.date.month}/${e.date.day}'
                    : '${e.date.month}/${e.date.day} 一起付的',
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

  /// What a sum owed was for: its note, or the merchant or note of the
  /// spending it was paid in.
  String _owedTitle(Entry e) {
    final lead = _ledger.groupLead(e);
    for (final words in [e.note, lead.merchant, lead.note]) {
      if (words.isNotEmpty) return words;
    }
    return '代墊';
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
    final account = await _addPerson();
    if (account == null) return;
    _set(() {
      _f.to = account.id;
      _paying = {};
    });
  }
}

/// The people money can be paid for, to tick any number of them: those
/// already in the spending ticked, 新增對象 at the end, and a button to
/// take the ticked ones back to the form.
class _PeopleChoices extends StatefulWidget {
  const _PeopleChoices({
    required this.people,
    required this.selected,
    required this.color,
    required this.onDone,
    required this.onAdd,
  });

  final List<Account> people;
  final List<String> selected;
  final Color color;
  final ValueChanged<List<String>> onDone;
  final Future<Account?> Function() onAdd;

  @override
  State<_PeopleChoices> createState() => _PeopleChoicesState();
}

class _PeopleChoicesState extends State<_PeopleChoices> {
  late final _people = [...widget.people];
  late final _picked = [...widget.selected];

  @override
  Widget build(BuildContext context) {
    const adding = '';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OptionGrid<String>(
          columns: 3,
          ring: widget.color,
          selected: null,
          chosen: {..._picked},
          options: [
            for (final a in _people)
              Option(a.id, a.name, Glyph.heart, Hue.muted),
            const Option(adding, '新增對象', Glyph.add, Hue.muted),
          ],
          onPick: (id) async {
            if (id != adding) {
              setState(() {
                if (!_picked.remove(id)) _picked.add(id);
              });
              return;
            }
            final made = await widget.onAdd();
            if (made == null || !mounted) return;
            setState(() {
              _people.add(made);
              _picked.add(made.id);
            });
          },
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 52,
          child: FilledButton(
            onPressed: () => widget.onDone(_picked),
            style: FilledButton.styleFrom(
              backgroundColor: widget.color,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            child: Text(
              _picked.isEmpty ? '不代墊' : '好了（${_picked.length} 人）',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
  }
}
