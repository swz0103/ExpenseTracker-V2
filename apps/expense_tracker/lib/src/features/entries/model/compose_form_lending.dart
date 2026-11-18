part of 'compose_form.dart';

// 代墊 and 對方還錢: whom an entry was paid for, and what each owes.

extension Lending on ComposeForm {
  /// Opens a transfer to or from someone's account as 代墊 or 還款.
  void findLending(Entry entry) {
    if (entry.type != EntryType.transfer) return;
    final other = entry.to;
    if (other == null) return;
    if (ledger.account(other).kind == AccountKind.receivable) {
      // Paid for someone: a spending of which none is one's own.
      mode = ComposeMode.expense;
      back = false;
      lent = [(other, entry.amount)];
      _lentIds[other] = entry.id;
      _ids.add(entry.id);
      final common = categoryChoices();
      category = common.isEmpty ? '' : common.first;
    } else if (ledger.account(entry.account).kind == AccountKind.receivable) {
      // Saved from the person to the account; the form keeps the person
      // in [to] either way.
      mode = ComposeMode.lend;
      back = true;
      account = other;
      to = entry.account;
    }
  }

  /// Puts the entries written as one with [entry] in the fields: the
  /// spending, and what was paid in it for each person.
  void loadGroup(Entry entry) {
    final members = ledger.entryQueryService.groupOf(entry);
    final own = [
      for (final m in members)
        if (m.type == EntryType.expense) m,
    ];
    final others = [
      for (final m in members)
        if (m.type == EntryType.transfer && m.to != null) m,
    ];
    load(own.isEmpty ? members.first : own.first);
    mode = ComposeMode.expense;
    if (own.isEmpty) {
      final common = categoryChoices();
      category = common.isEmpty ? '' : common.first;
      merchant = '';
    }
    _group = entry.group;
    _ownId = own.isEmpty ? null : own.first.id;
    _ids.addAll([for (final m in members) m.id]);
    for (final m in others) {
      _lentIds[m.to!] = m.id;
    }
    lent = [for (final m in others) (m.to!, m.amount)];
    amount = members.fold(0, (sum, m) => sum + m.amount);
  }

  /// The ids of the entries the form was opened from: one, or all those
  /// written as one with it.
  Set<String> get openedIds => {..._ids, ?editing?.id};

  /// Starts paying for [people] in this spending, or changes who: the
  /// amount is shared evenly, one's own share counted too, the rest of a
  /// cent going to one's own. Splitting stops, as the two do not mix.
  void lendTo(List<String> people) {
    if (people.isEmpty) {
      lent = null;
      return;
    }
    parts = null;
    final share = amount ~/ (people.length + 1);
    lent = [for (final p in people) (p, share)];
  }

  /// What is paid for the person at [index] changed.
  void setLent(int index, int value) {
    final now = lent;
    if (now == null) return;
    lent = [
      for (final (i, p) in now.indexed)
        if (i == index) (p.$1, value) else p,
    ];
  }

  /// Back to a spending all one's own.
  void stopLending() => lent = null;

  /// Paying for others in a spending.
  bool get lending => mode == ComposeMode.expense && lent != null;

  /// One's own share of a spending paid partly for others.
  int get own =>
      amount -
      (lent ?? const <(String, int)>[]).fold(0, (sum, p) => sum + p.$2);

  /// The tab showing: 代墊 sits under 支出, 還款 under 收入.
  ComposeMode get tab => switch (mode) {
    ComposeMode.lend => back ? ComposeMode.income : ComposeMode.expense,
    final mode => mode,
  };

  /// 代墊 from the expense tab, 對方還錢 from the income tab; the amount,
  /// date and notes stay.
  void lend({required bool back}) {
    mode = ComposeMode.lend;
    this.back = back;
    parts = null;
    installments = 0;
    final main = ledger.accounts.main;
    if (main.isNotEmpty) account = main;
    final known = {for (final a in people) a.id};
    if (!known.contains(to)) to = people.isEmpty ? '' : people.first.id;
  }

  /// Everything the person in [to] owes is being paid back: each sum
  /// ticked and the amount all they owe.
  void payAll() {
    if (to.isEmpty) return;
    paying = {for (final (e, _) in ledger.reportService.owedBy(to)) e.id};
    final owed = ledger.balanceService.balance(to);
    if (owed > 0) setAmount(owed);
  }

  /// One sum ticked or not among what is being paid back; the amount
  /// follows: all they owe but the sums not ticked, which stay owed.
  void togglePaying(String id) {
    paying = {...paying};
    if (!paying.remove(id)) paying.add(id);
    final kept = ledger.reportService
        .owedBy(to)
        .fold(0, (sum, o) => paying.contains(o.$1.id) ? sum : sum + o.$2);
    final left = ledger.balanceService.balance(to) - kept;
    setAmount(left < 0 ? 0 : left);
  }
}
