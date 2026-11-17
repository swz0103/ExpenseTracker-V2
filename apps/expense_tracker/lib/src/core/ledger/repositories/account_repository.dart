import '../models/models.dart';

/// What the screens and queries may ask of the accounts.
abstract interface class AccountReader {
  /// Every account, archived ones included, in the order they came; the
  /// list cannot be changed.
  List<Account> get all;

  /// The accounts still open, in their order.
  List<Account> get open;

  /// The account [id], or null when the book has none.
  Account? byId(String id);

  /// Whether [id] is an account of this book, archived ones included.
  bool contains(String id);

  /// The account [id]; when the book has none, as for an entry whose
  /// account was never kept, a bank account of that name with nothing in
  /// it, so a sum still adds up.
  Account resolve(String id);

  /// The account money usually comes from or goes back to, as for a card
  /// payment or money paid back: the first open NT$ bank account, else
  /// any open NT$ account that is not a debt; empty when there is none.
  String get main;
}

/// The book's accounts with an index by id. The commands that write use
/// it; the screens see an [AccountReader].
final class AccountRepository implements AccountReader {
  AccountRepository([Iterable<Account> accounts = const []])
    : _items = [...accounts];

  final List<Account> _items;
  Map<String, Account>? _byId;

  Map<String, Account> get _index =>
      _byId ??= {for (final a in _items) a.id: a};

  void _changed() => _byId = null;

  @override
  List<Account> get all => List.unmodifiable(_items);

  @override
  List<Account> get open => [
    for (final a in _items)
      if (!a.archived) a,
  ];

  @override
  Account? byId(String id) => _index[id];

  @override
  bool contains(String id) => _index.containsKey(id);

  @override
  Account resolve(String id) =>
      _index[id] ?? Account(id, id, AccountKind.bank, 0);

  @override
  String get main {
    final usable = [
      for (final a in open)
        if (!a.kind.isDebt && !a.foreign && a.kind != AccountKind.receivable) a,
    ];
    for (final a in usable) {
      if (a.kind == AccountKind.bank) return a.id;
    }
    return usable.isEmpty ? '' : usable.first.id;
  }

  /// Adds [account] last; its id is the caller's to make unique.
  void add(Account account) {
    _items.add(account);
    _changed();
  }

  /// Adds those of [accounts] whose id the book does not have yet, in
  /// order, and returns them; a second with the same id is left out too.
  List<Account> addNew(Iterable<Account> accounts) {
    final ids = {for (final a in _items) a.id};
    final added = [
      for (final a in accounts)
        if (ids.add(a.id)) a,
    ];
    if (added.isEmpty) return added;
    _items.addAll(added);
    _changed();
    return added;
  }

  /// Puts [account] in place of the one with its id, where it stands, and
  /// returns the one replaced; null, changing nothing, when there is none.
  Account? replace(Account account) {
    final index = _items.indexWhere((a) => a.id == account.id);
    if (index < 0) return null;
    final replaced = _items[index];
    _items[index] = account;
    _changed();
    return replaced;
  }

  /// Gives the accounts of [ids] those places, in that order, as dragged
  /// on 我的帳戶, and returns those whose place changed.
  List<Account> place(List<String> ids) {
    final moved = <Account>[];
    for (final (place, id) in ids.indexed) {
      final index = _items.indexWhere((a) => a.id == id);
      if (index < 0 || _items[index].place == place) continue;
      _items[index] = _items[index].copyWith(place: place);
      moved.add(_items[index]);
    }
    if (moved.isNotEmpty) _changed();
    return moved;
  }

  /// Takes away the account [id] and returns it; null when there is none.
  Account? remove(String id) {
    final index = _items.indexWhere((a) => a.id == id);
    if (index < 0) return null;
    final removed = _items.removeAt(index);
    _changed();
    return removed;
  }

  /// Takes the accounts of [accounts], in their order, as when the book
  /// is read again.
  void replaceWith(Iterable<Account> accounts) {
    final copy = [...accounts];
    _items
      ..clear()
      ..addAll(copy);
    _changed();
  }
}
