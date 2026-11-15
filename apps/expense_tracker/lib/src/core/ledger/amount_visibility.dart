import 'package:flutter/foundation.dart' show ChangeNotifier;

/// Whether amounts are written as dots: the 隱藏金額 switch. A choice for
/// this visit only, never kept, so it starts shown; and nothing worked out
/// from the book rests on it.
final class AmountVisibility extends ChangeNotifier {
  bool get hidden => _hidden;
  var _hidden = false;

  void toggle() {
    _hidden = !_hidden;
    notifyListeners();
  }

  /// Shows amounts again, as for a book started over.
  void reset() {
    if (!_hidden) return;
    _hidden = false;
    notifyListeners();
  }
}
