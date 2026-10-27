/// What a home-screen shortcut, the widget or a notification opens: the
/// composer on a new expense or a new income. The phone passes its [name].
enum QuickAction {
  expense,
  income;

  /// The action called [name], or null for none the app knows.
  static QuickAction? named(String? name) {
    for (final action in values) {
      if (action.name == name) return action;
    }
    return null;
  }
}
