final class Budget {
  const Budget(
    this.category,
    this.limit, {
    this.warning = 80,
    this.carry = false,
    this.since,
  });

  /// A category name, [Ledger.allSpending] for the total, or `#` and a
  /// tag for the spending carrying it, such as `#旅遊`.
  final String category;
  final int limit;

  /// The tag of a tag budget; null for a category or the total.
  String? get tag => category.startsWith('#') ? category.substring(1) : null;

  /// The share used, in percent, at which the budget warns.
  final int warning;

  /// Whether what was left of last month's limit is added to this month's.
  final bool carry;

  /// The first day of the first month the budget counts; null when not
  /// known.
  final DateTime? since;

  /// This budget under the name [category], as when it is renamed.
  Budget renamed(String category) =>
      Budget(category, limit, warning: warning, carry: carry, since: since);
}
