part of 'composer.dart';

// Picking whom 代墊 is for or from: choices opened in the form's place.

extension _LendPickers on _ComposerState {
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
