part of 'vault_journal.dart';

/// Reading the ledger back into the screens' book: accounts, categories,
/// entries, budgets and recurring items as the screens show them, and the
/// starter categories and accounts of a new ledger.
extension _Loading on VaultJournal {
  Future<ui.Ledger> _load() async {
    if (_store.categories(_workspace).isEmpty) await _addStarters();
    if (_store.accounts(_workspace).isEmpty) await _addStarterAccounts();
    final looks = _looks.all();
    final categories = {for (final c in _store.categories(_workspace)) c.id: c};
    final tags = {for (final t in _store.tags(_workspace)) t.id: t};
    final merchants = {for (final m in _store.merchants(_workspace)) m.id: m};
    final reversed = _store.reversedPostings(_workspace);
    final instalments = _store.instalmentPurchases(_workspace);
    final confirmed = _recurringLinks();
    final postingTags = _store.postingTags(_workspace);
    final postingMerchants = _store.postingMerchants(_workspace);
    final notes = _store.postingNotes(_workspace);
    final homes = _store.postingHomeValues(_workspace);
    if (_rates.isEmpty) _rates.addAll(_keptRates());
    if (_quotes.isEmpty) _restoreQuotes();
    final carries = _carries();
    String nameOf(PublicId id) =>
        _live(categories, id, (c) => c.replacementId)?.name ?? '';
    String merchantOf(PublicId? id) {
      if (id == null) return '';
      final merchant = _live(merchants, id, (m) => m.replacementId);
      return merchant == null || merchant.archived ? '' : merchant.name;
    }

    final openings = <PublicId, int>{};
    final entries = <ui.Entry>[];
    for (final posting in _store.workspacePostings(_workspace)) {
      if (reversed.contains(posting.id)) continue;
      if (posting.kind == PostingKind.opening) {
        for (final leg in posting.legs) {
          final id = leg.account.id;
          openings[id] = (openings[id] ?? 0) + _int(leg.amount);
        }
        continue;
      }
      final tagNames = <String>[];
      for (final id in postingTags[posting.id] ?? const <PublicId>[]) {
        final tag = _live(tags, id, (t) => t.replacementId);
        if (tag != null && !tag.archived) tagNames.add(tag.name);
      }
      final entry = _entryOf(
        posting,
        category: nameOf,
        tags: tagNames,
        merchant: merchantOf(postingMerchants[posting.id]),
        note: notes[posting.id] ?? '',
        home: homes[posting.id],
        recurring: confirmed[posting.id]?.value,
        installments: instalments.contains(posting.id)
            ? _store.installments(posting.id).length
            : 0,
      );
      if (entry != null) entries.add(entry);
    }
    final (trades, holdings) = _investments(notes);
    entries.addAll(trades);
    final today = _clock.today();
    final applying = _applying(categories);
    final removed = _removedTemplates();
    final accounts = _store.accounts(_workspace);
    return ui.Ledger(
      today: DateTime.utc(today.year, today.month, today.day),
      accounts: [
        for (final a in accounts)
          _accountOf(a, openings[a.id] ?? 0, looks[a.id.value]),
      ],
      cardDues: _cardDues(accounts, today),
      categories: [
        for (final c in categories.values)
          if (c.replacementId == null)
            _categoryOf(c, categories, looks[c.id.value]),
      ],
      entries: entries,
      holdings: holdings,
      moves: _moves,
      quotedOn: _quotedOn,
      budgets: [
        for (final MapEntry(key: key, value: plan) in applying.entries)
          ui.Budget(
            key,
            _int(plan.limit),
            warning: plan.warningPercent,
            carry: carries[plan.id.value] ?? false,
            since: DateTime.utc(plan.month.year, plan.month.month),
          ),
      ],
      rates: _rates,
      trash: _trash(),
      recurring: [
        for (final (template, active) in _store.recurringTemplates(_workspace))
          if (!removed.contains(template.id.value))
            _recurringOf(
              template,
              active: active,
              category: nameOf,
              merchant: merchantOf,
            ),
      ],
      journal: this,
    );
  }

  /// The screens' entry for [posting]; null for kinds not shown yet, such
  /// as trades.
  ui.Entry? _entryOf(
    Posting posting, {
    required String Function(PublicId id) category,
    required List<String> tags,
    required String merchant,
    required String note,
    required int installments,
    Money? home,
    String? recurring,
  }) {
    final date = DateTime.utc(
      posting.date.year,
      posting.date.month,
      posting.date.day,
    );
    final principal = [
      for (final leg in posting.legs)
        if (leg.role == LegRole.principal) leg,
    ];
    final fee = posting.legs
        .where((leg) => leg.role == LegRole.fee)
        .fold(0, (sum, leg) => sum + _int(leg.amount).abs());
    switch (posting.kind) {
      case PostingKind.income || PostingKind.expense || PostingKind.refund:
        final income = posting.kind != PostingKind.expense;
        final parts = [
          for (final a in posting.allocations)
            (category(a.categoryId), _int(a.amount)),
        ];
        final amount = posting.legs.fold(
          0,
          (sum, leg) => sum + _int(leg.amount),
        );
        final fallback = income ? '其他收入' : ui.feeCategory;
        return ui.Entry(
          id: posting.id.value,
          date: date,
          type: income ? ui.EntryType.income : ui.EntryType.expense,
          amount: amount.abs(),
          account: posting.legs.first.account.id.value,
          category: parts.isEmpty ? fallback : parts.first.$1,
          note: note,
          merchant: merchant,
          tags: tags,
          parts: parts.length > 1 ? parts : const [],
          refundOf: posting.refundOf?.value,
          installments: installments,
          recurring: recurring,
          home: home == null ? null : _int(home),
        );
      case PostingKind.transfer:
        final from = principal.where((leg) => _int(leg.amount) < 0);
        final to = principal.where((leg) => _int(leg.amount) > 0);
        if (from.isEmpty || to.isEmpty) return null;
        final sent = from.first.amount;
        final arrived = to.first.amount;
        return ui.Entry(
          id: posting.id.value,
          date: date,
          type: ui.EntryType.transfer,
          amount: _int(sent).abs(),
          account: from.first.account.id.value,
          to: to.first.account.id.value,
          category: '轉帳',
          note: note,
          fee: fee,
          received: arrived.currency == sent.currency ? null : _int(arrived),
        );
      default:
        return null;
    }
  }

  /// What is still to pay on each card's last closed statement, as the
  /// ledger's own billing works it out.
  Map<String, int> _cardDues(List<Account> accounts, BusinessDate today) {
    final dues = <String, int>{};
    for (final a in accounts) {
      if (a.kind != AccountKind.creditCard) continue;
      final terms = _store.cardTerms(a.id);
      if (terms == null) continue;
      final closed = terms.cycleFor(today).startsAfter;
      final due = _int(_store.statement(a.id, closed).remainingDue);
      dues[a.id.value] = due < 0 ? 0 : due;
    }
    return dues;
  }

  ui.Account _accountOf(Account a, int opening, Look? look) {
    final card = a.kind == AccountKind.creditCard;
    final terms = card ? _store.cardTerms(a.id) : null;
    final limit = terms?.limit;
    return ui.Account(
      a.id.value,
      a.name,
      _uiKind(a.kind),
      opening,
      closes: {
        if (terms != null)
          for (final o in terms.overrides)
            _date(o.scheduledClose): _date(o.closesOn),
      },
      icon: look?.icon,
      closingDay: terms?.closingDay,
      dueDay: terms?.dueDay,
      limit: limit == null ? null : _int(limit),
      archived: a.state != AccountState.active,
      inNetWorth: a.includeInNetWorth,
      currency: a.currency.code,
    );
  }

  ui.Category _categoryOf(Category c, Map<PublicId, Category> all, Look? look) {
    final income = c.kind == CategoryKind.income;
    final parentId = c.parentId;
    final starter = _starters.where((s) => s.$1 == c.name).firstOrNull;
    final icon = look?.icon ?? starter?.$2 ?? (income ? 'income' : 'other');
    final hash = c.name.codeUnits.fold(0, (h, u) => h + u);
    final shade = _palette[hash % _palette.length];
    final color = look?.color ?? starter?.$3 ?? shade;
    return ui.Category(
      c.name,
      icon,
      Color(color),
      income: income,
      parent: parentId == null ? null : all[parentId]?.name,
      archived: c.archived,
    );
  }

  /// A new ledger's categories.
  Future<void> _addStarters() async {
    for (final (name, icon, color, income) in _starters) {
      final id = PublicId.generate();
      final kind = income ? CategoryKind.income : CategoryKind.expense;
      await _catalog(CatalogType.category, CreateEntry(id, name, kind: kind));
      await _looks.save(id.value, (icon: icon, color: color));
    }
  }

  /// A cash and a bank account for a ledger that has never had one, so
  /// the first entry can be written at once.
  Future<void> _addStarterAccounts() async {
    for (final (name, kind) in const [
      ('現金', ui.AccountKind.cash),
      ('銀行帳戶', ui.AccountKind.bank),
    ]) {
      await _open(ui.Account(PublicId.generate().value, name, kind, 0));
    }
  }
}
