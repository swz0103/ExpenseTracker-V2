import 'ids.dart';

/// The five classes of double entry: all the journal knows of what an
/// account is. "Bank", "card", "category" are its owner's [LedgerAccount.tag].
enum AccountClass {
  asset,
  liability,
  equity,
  income,
  expense;

  /// Counted in net worth when the account says so: what is held and
  /// what is owed.
  bool get isBalanceSheet => this == asset || this == liability;

  /// What a period's income and spending are read from.
  bool get isFlow => this == income || this == expense;
}

/// One account of the journal's tree.
final class LedgerAccount {
  const LedgerAccount({
    required this.id,
    required this.cls,
    required this.name,
    required this.owner,
    this.parent,
    this.currency,
    this.commodity,
    this.tag = '',
    this.inNetWorth = true,
    this.inFlowReports = true,
  });

  final AccountId id;
  final AccountClass cls;
  final String name;

  /// Who added the account; a book can hold accounts of an owner the app
  /// no longer has.
  final OwnerId owner;
  final AccountId? parent;

  /// The one currency postings here are in; null takes any (categories,
  /// equity).
  final CurrencyCode? currency;

  /// What a posting's quantity counts here, such as a stock's code; null
  /// for money.
  final String? commodity;

  /// The owner's own word for the account, such as `card`.
  final String tag;

  /// Counted in net worth (an asset or a liability the person counts).
  final bool inNetWorth;

  /// For an income or spending account: whether a period's income and
  /// spending count it. A realised gain is income to an accountant, not
  /// to the person's 收支.
  final bool inFlowReports;

  @override
  bool operator ==(Object other) =>
      other is LedgerAccount &&
      other.id == id &&
      other.cls == cls &&
      other.name == name &&
      other.owner == owner &&
      other.parent == parent &&
      other.currency == currency &&
      other.commodity == commodity &&
      other.tag == tag &&
      other.inNetWorth == inNetWorth &&
      other.inFlowReports == inFlowReports;

  @override
  int get hashCode => Object.hash(
    id,
    cls,
    name,
    owner,
    parent,
    currency,
    commodity,
    tag,
    inNetWorth,
    inFlowReports,
  );
}

/// Every account of a book, by id.
final class AccountTree {
  AccountTree([Iterable<LedgerAccount> accounts = const []]) {
    accounts.forEach(put);
  }

  final _byId = <AccountId, LedgerAccount>{};

  /// Adds [account], or puts it in place of the one with its id.
  void put(LedgerAccount account) => _byId[account.id] = account;

  LedgerAccount? operator [](AccountId id) => _byId[id];

  /// Every account, in the order first added.
  Iterable<LedgerAccount> get all => _byId.values;

  /// The accounts of [cls], [tag] and [owner], each when given.
  Iterable<LedgerAccount> where({
    AccountClass? cls,
    String? tag,
    OwnerId? owner,
  }) => _byId.values.where(
    (a) =>
        (cls == null || a.cls == cls) &&
        (tag == null || a.tag == tag) &&
        (owner == null || a.owner == owner),
  );
}
