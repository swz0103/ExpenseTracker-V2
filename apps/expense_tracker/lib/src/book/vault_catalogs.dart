part of 'vault_journal.dart';

/// Categories, tags and merchants: finding the ledger's live entry for a
/// name the screens use, and making it when there is none.
extension _Catalogs on VaultJournal {
  Future<void> _catalog(CatalogType type, CatalogChange change) async {
    await _books.changeCatalog(
      ChangeCatalog(operation: _op(), catalog: type, change: change),
    );
  }

  Category _categoryById(PublicId id) =>
      _store.categories(_workspace).firstWhere((c) => c.id == id);

  PublicId? _categoryId(String? name, CategoryKind kind) {
    if (name == null) return null;
    for (final c in _store.categories(_workspace)) {
      if (c.replacementId == null && c.kind == kind && c.name == name) {
        return c.id;
      }
    }
    return null;
  }

  /// The live category [name] of the kind, made when there is none.
  Future<Category> _category(String name, {required bool income}) async {
    final kind = income ? CategoryKind.income : CategoryKind.expense;
    final found = _categoryId(name, kind);
    if (found != null) return _categoryById(found);
    final id = PublicId.generate();
    await _catalog(CatalogType.category, CreateEntry(id, name, kind: kind));
    return _categoryById(id);
  }

  /// The categories of [e], counted in the currency of the [account] it
  /// is booked in; a foreign entry is never split.
  Future<List<CategoryShare>> _shares(
    ui.Entry e, {
    required bool income,
    Account? account,
  }) {
    final currency = account?.currency ?? homeCurrency;
    final parts = e.parts.isNotEmpty && currency == homeCurrency
        ? e.parts
        : [if (e.category.isNotEmpty) (e.category, e.amount)];
    return _sharesOf(parts, income: income, currency: currency);
  }

  /// The category of a transfer's [fee], none without one.
  Future<List<CategoryShare>> _feeShares(int fee) async {
    if (fee <= 0) return const [];
    return _sharesOf([(ui.feeCategory, fee)], income: false);
  }

  Future<List<CategoryShare>> _sharesOf(
    List<(String, int)> parts, {
    required bool income,
    Currency? currency,
  }) async {
    final shares = <CategoryShare>[];
    for (final (name, amount) in parts) {
      final c = await _category(name, income: income);
      final money = Money(currency ?? homeCurrency, BigInt.from(amount));
      shares.add(CategoryShare(c.id, c.version, money));
    }
    return shares;
  }

  List<_Label> _labels({required bool merchant}) => merchant
      ? [
          for (final m in _store.merchants(_workspace))
            if (m.replacementId == null)
              (id: m.id, name: m.name, version: m.version),
        ]
      : [
          for (final t in _store.tags(_workspace))
            if (t.replacementId == null)
              (id: t.id, name: t.name, version: t.version),
        ];

  /// The live tag or merchant [name], made or brought back when needed.
  Future<_Label> _label(String name, {required bool merchant}) async {
    final type = merchant ? CatalogType.merchant : CatalogType.tag;
    _Label? find() =>
        _labels(merchant: merchant).where((l) => l.name == name).firstOrNull;
    final found = find();
    if (found == null) {
      await _catalog(type, CreateEntry(PublicId.generate(), name));
    } else if (_archived(found.id, merchant: merchant)) {
      await _catalog(
        type,
        ArchiveEntry(found.id, found.version, archived: false),
      );
    } else {
      return found;
    }
    final made = find();
    if (made == null) throw StateError('「$name」was not kept.');
    return made;
  }

  bool _archived(PublicId id, {required bool merchant}) => merchant
      ? _store.merchants(_workspace).any((m) => m.id == id && m.archived)
      : _store.tags(_workspace).any((t) => t.id == id && t.archived);

  Future<List<TagSelection>> _tags(List<String> names) async {
    final selections = <TagSelection>[];
    for (final name in {...names}) {
      final tag = await _label(name, merchant: false);
      selections.add(TagSelection(tag.id, tag.version));
    }
    return selections;
  }

  Future<MerchantSelection?> _merchant(String name) async {
    if (name.isEmpty) return null;
    final merchant = await _label(name, merchant: true);
    return MerchantSelection(merchant.id, merchant.version);
  }
}
