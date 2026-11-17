part of 'ledger.dart';

// What the entries are kept in and under: accounts, categories, budgets,
// tags and merchants, with their order, names and merging.

extension LedgerSetup on Ledger {
  void setBudget(String category, int limit, {int? warning, bool? carry}) {
    final old = budgetFor(category);
    final budget = Budget(
      category,
      limit,
      warning: warning ?? old.warning,
      carry: carry ?? old.carry,
      since: old.since ?? DateTime.utc(today.year, today.month),
    );
    _budgets.put(budget);
    _changed(const {Topic.budgets});
    _keep(WriteBatch(budgets: [budget]));
  }

  void removeBudget(String category) {
    _budgets.remove(category);
    _changed(const {Topic.budgets});
    _keep(WriteBatch(dropped: [(Collection.budget, category)]));
  }

  void addAccount(Account account) {
    _accounts.add(account);
    _changed(const {Topic.accounts});
    _keep(WriteBatch(accounts: [account]));
  }

  /// Puts [account] in place of the one with the same id.
  void updateAccount(Account account) {
    final before = _accounts.byId(account.id);
    if (before == null) return addAccount(account);
    // A form that does not show a card's moved closes and earlier billing
    // days keeps them.
    account = account.copyWith(
      closes: account.closes.isEmpty ? before.closes : null,
      history: account.history.isEmpty ? before.history : null,
    );
    account = _rescheduled(before, account);
    _accounts.replace(account);
    _changed(const {Topic.accounts});
    _keep(WriteBatch(accounts: [account]));
  }

  /// [after] keeping [before]'s billing days for the statements closing
  /// before the next close on the new day, as the ledger keeps them.
  Account _rescheduled(Account before, Account after) {
    final closing = before.closingDay;
    final due = before.dueDay;
    if (after.kind != AccountKind.card ||
        closing == null ||
        due == null ||
        ((after.closingDay ?? closing) == closing &&
            (after.dueDay ?? due) == due)) {
      return after;
    }
    final day = after.closingDay ?? closing;
    var from = DateTime.utc(today.year, today.month + 1, 0);
    for (final month in [today.month, today.month + 1]) {
      final last = DateTime.utc(today.year, month + 1, 0);
      final close = DateTime.utc(last.year, last.month, min(day, last.day));
      if (close.isAfter(today)) {
        from = close;
        break;
      }
    }
    final until = BusinessDate(from.year, from.month, from.day);
    final kept = before.history;
    // Days changed again before the last change took effect: the days
    // before that one still hold until the first close on the newest.
    final pending =
        kept.isNotEmpty &&
        kept.last.until.compareTo(
              BusinessDate(today.year, today.month, today.day),
            ) >
            0;
    return after.copyWith(
      history: [
        ...(pending ? kept.sublist(0, kept.length - 1) : kept),
        CardScheduleChange(
          until: until,
          closingDay: pending ? kept.last.closingDay : closing,
          dueDay: pending ? kept.last.dueDay : due,
        ),
      ],
    );
  }

  /// Puts the categories of [names] in that order, as dragged on 分類;
  /// the others keep their places after them.
  void placeCategories(List<String> names) {
    final moved = _categories.place(names);
    if (moved.isEmpty) return;
    _changed(const {Topic.categories});
    _keep(WriteBatch(categories: moved));
  }

  /// Puts the accounts of [ids] in that order on 我的帳戶; the others
  /// keep their places.
  void placeAccounts(List<String> ids) {
    final moved = _accounts.place(ids);
    if (moved.isEmpty) return;
    _changed(const {Topic.accounts});
    _keep(WriteBatch(accounts: moved));
  }

  /// Corrects [id]'s balance today to [target] by moving its opening
  /// balance, so its history keeps its shape.
  void setBalance(String id, int target) {
    final a = _accounts.byId(id);
    if (a == null) return;
    final moved = a.copyWith(opening: a.opening + target - balance(id));
    _accounts.replace(moved);
    _changed(const {Topic.accounts});
    _keep(WriteBatch(accounts: [moved]));
  }

  /// Moves the close of [cardId]'s statement scheduled on [scheduled] to
  /// [closesOn], up to a week either way, as a bank does around a holiday.
  void moveClose(String cardId, DateTime scheduled, DateTime closesOn) {
    final card = _accounts.byId(cardId);
    if (card == null) return;
    final moved = card.copyWith(closes: {...card.closes, scheduled: closesOn});
    _accounts.replace(moved);
    notifyListeners();
    _keep(WriteBatch(accounts: [moved]));
  }

  /// Whether anything still names account [id]: an entry, one in the
  /// trash that may come back, or a recurring item. One in use is
  /// archived rather than deleted, so nothing is left pointing nowhere.
  bool isUsed(String id) =>
      _entries.any((e) => e.account == id || e.to == id) ||
      _trash.mentionsAccount(id) ||
      _recurring.mentionsAccount(id);

  void removeAccount(String id) {
    if (isUsed(id)) return;
    final removed = _accounts.remove(id);
    if (removed == null) return;
    notifyListeners();
    _keep(WriteBatch(dropped: [(Collection.account, removed.id)]));
  }

  /// Whether [name] can be a new category's: not empty, not one the
  /// ledger keeps for itself (all spending, transfers, a `#` tag budget)
  /// and not taken, unless by [except].
  bool categoryNameFree(String name, {String? except}) =>
      _categories.isNameFree(name, except: except);

  /// [category] under its name without the spaces around it, as every
  /// name is compared.
  Category _trimmed(Category category) {
    final name = category.name.trim();
    return name == category.name ? category : category.copyWith(name: name);
  }

  void addCategory(Category category) {
    if (!categoryNameFree(category.name)) {
      problem.value = const NameTaken();
      return;
    }
    category = _trimmed(category);
    _categories.add(category);
    _changed(const {Topic.categories});
    _keep(WriteBatch(categories: [category]));
  }

  void _renameCategory(String from, String to) {
    if (from == to || to.isEmpty) return;
    _categories.rename(from, to);
    _moveUses(from, to);
    _budgets.rename(from, to);
    notifyListeners();
  }

  /// Puts the entries, the deleted entries and the recurring items of
  /// category [from] in [to]: what comes back from 最近刪除 fits the book
  /// as it is now, not as it was.
  void _moveUses(String from, String to) {
    for (final (i, e) in _entries.indexed) {
      if (e.category == from || e.parts.any((p) => p.$1 == from)) {
        _entries[i] = e.withCategory(to, from: from);
      }
    }
    _trash.changeEntries(
      (e) => e.category == from || e.parts.any((p) => p.$1 == from)
          ? e.withCategory(to, from: from)
          : null,
    );
    _recurring.renameCategory(from, to);
  }

  /// Changes a category's place, name, mark, colour or archive state; a
  /// new name reaches every entry, budget and recurring item that uses it.
  void updateCategory(String name, Category next) {
    if (_categories.all.every((c) => c.name != name)) return;
    if (!categoryNameFree(next.name, except: name)) {
      problem.value = const NameTaken();
      return;
    }
    next = _trimmed(next);
    final before = _before;
    final renamed = next.name != name;
    if (renamed) _renameCategory(name, next.name);
    // Whatever the edit built, it is still the category it was, in the
    // place it was dragged to.
    final kept = _categories.replace(renamed ? next.name : name, next)!;
    notifyListeners();
    // Records are kept under the category's id, so a new name is one row.
    _keep(renamed ? WriteBatch(categories: [kept]) : _since(before));
  }

  /// Moves everything in [from] to [into] and removes [from].
  void mergeCategory(String from, String into) {
    if (from == into) return;
    final before = _before;
    _moveUses(from, into);
    _budgets.remove(from);
    _categories.removeMerged(from);
    notifyListeners();
    _keep(_since(before));
  }

  /// Renames or merges a tag across every entry; an empty [to] removes it.
  void renameTag(String from, String to) {
    final before = _before;
    if (to.isEmpty) {
      _budgets.remove('#$from');
    } else {
      _budgets.rename('#$from', '#$to');
    }
    for (final (i, e) in _entries.indexed) {
      if (!e.tags.contains(from)) continue;
      final tags = {
        for (final t in e.tags)
          if (t != from) t,
        if (to.isNotEmpty) to,
      }.toList();
      _entries[i] = e.withLabels(tags: tags);
    }
    _trash.changeEntries(
      (e) => e.tags.contains(from)
          ? e.withLabels(
              tags: {
                for (final t in e.tags)
                  if (t != from) t,
                if (to.isNotEmpty) to,
              }.toList(),
            )
          : null,
    );
    notifyListeners();
    _keep(_since(before));
  }

  /// Renames or merges a merchant across every entry; an empty [to]
  /// clears it.
  void renameMerchant(String from, String to) {
    final before = _before;
    for (final (i, e) in _entries.indexed) {
      if (e.merchant == from) _entries[i] = e.withLabels(merchant: to);
    }
    _trash.changeEntries(
      (e) => e.merchant == from ? e.withLabels(merchant: to) : null,
    );
    notifyListeners();
    _keep(_since(before));
  }
}
