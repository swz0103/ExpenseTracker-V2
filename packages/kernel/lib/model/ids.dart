/// Typed ids: extension types over the text they are kept as, so an
/// account's id cannot be passed where an intent's is wanted, at no cost
/// when the program runs.
library;

/// An account of the journal: a money account, a category, a holding.
extension type const AccountId(String value) implements Object {}

/// An intent: one record the person kept, such as a spending.
extension type const IntentId(String value) implements Object {}

/// What kind of intent a record is, such as `spending`; each kind has
/// one posting rule.
extension type const IntentType(String value) implements Object {}

/// Who registered an intent type, an amender or an account.
extension type const OwnerId(String value) implements Object {}

/// The code of a currency an amount is kept in, such as `TWD`.
extension type const CurrencyCode(String value) implements Object {}
