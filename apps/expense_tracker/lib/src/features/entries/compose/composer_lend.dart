part of 'composer.dart';

/// The 代墊 fields: whom the money is for or from, and the person's own
/// account that keeps what they owe.
extension _LendFields on _ComposerState {
  /// 代墊 under 支出 (paid for someone) or 對方還錢 under 收入. Each
  /// person has an account of their own that keeps what they owe.
  List<Widget> _lendFields() {
    final person = _f.to.isEmpty ? null : _ledger.account(_f.to);
    final owed = person == null ? 0 : _ledger.balance(person.id);
    return [
      _categories(!_f.back),
      TileRow([
        Tile(
          icon: Glyph.heart,
          label: _f.back ? '誰還錢' : '幫誰付',
          value: person?.name ?? '新增對象',
          valueColor: person == null ? Hue.accent : Hue.ink,
          sub: person == null || owed == 0
              ? null
              : '目前欠 ${_ledger.money(owed)}',
          size: 15,
          onTap: _pickPerson,
        ),
      ]),
      TileRow([_accountTile(_f.back ? '收款帳戶' : '付款帳戶'), _dateTile()]),
      _extras(false),
    ];
  }

  /// Picks whom the money is for, or adds a new person.
  Future<void> _pickPerson() async {
    const adding = '';
    final picked = _f.people.isEmpty
        ? adding
        : await pickOption<String>(
            context,
            title: '代墊對象',
            selected: _f.to,
            columns: 3,
            options: [
              ...accountOptions(_ledger, among: _f.people),
              const Option(adding, '新增對象', Glyph.add, Hue.accent),
            ],
          );
    if (picked == null || !mounted) return;
    if (picked != adding) {
      _set(() => _f.to = picked);
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
    _set(() => _f.to = account.id);
  }
}
