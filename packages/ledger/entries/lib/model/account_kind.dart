/// The code of the currency the books are kept in: NT$.
const homeCode = 'TWD';

/// What an account is: where money is held, or owed.
enum AccountKind {
  cash,
  bank,
  wallet,
  card,
  loan,
  receivable;

  /// Kinds whose balance is owed rather than held.
  bool get isDebt => this == card || this == loan;
}

/// What the write rules need to know of an account an entry names: its
/// kind and the currency it is kept in. The app's own account record
/// carries much more; the rules read only this.
final class AccountFacts {
  const AccountFacts(this.kind, {this.currency = homeCode});

  final AccountKind kind;

  /// The code of the currency, such as TWD or USD.
  final String currency;

  /// Kept in a currency other than NT$.
  bool get foreign => currency != homeCode;
}
