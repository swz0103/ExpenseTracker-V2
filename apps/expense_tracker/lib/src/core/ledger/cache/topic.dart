/// The parts of the ledger a change can touch, so what rests on the others
/// is kept and a screen hears only of the parts it asked for.
enum Topic {
  entries,
  accounts,
  categories,
  budgets,
  recurring,
  market,

  /// How amounts are shown (隱藏金額); nothing worked out rests on it.
  display;

  /// Every part of the ledger whose records answers can rest on.
  static const all = {
    entries,
    accounts,
    categories,
    budgets,
    recurring,
    market,
  };
}
