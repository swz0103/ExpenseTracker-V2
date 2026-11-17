part of 'ledger.dart';

// The holdings, replayed from the starting positions and every trade
// whenever the trades change; a change that would sell shares not held
// is undone.

extension LedgerHoldings on Ledger {
  /// Works the holdings out again when [trades] were touched, then tells
  /// the screens the entries changed; an oversold trade is undone and
  /// rethrown.
  void _replayOrUndo(void Function() undo, {bool trades = true}) {
    if (trades) {
      try {
        _replay();
      } on StateError {
        undo();
        _replay();
        rethrow;
      }
    }
    _changed(const {Topic.entries});
  }

  /// [_replayOrUndo], telling a refusal through [problem] rather than
  /// throwing; false when refused.
  bool _tryReplay(void Function() undo, {required bool trades}) {
    try {
      _replayOrUndo(undo, trades: trades);
      return true;
    } on StateError {
      // Said to the person through problem.
      problem.value = const SharesShort();
      notifyListeners();
      return false;
    }
  }

  /// Whether [extra] can join the entries, in place of [replacing]: none
  /// of their trades sells more shares than are held by then.
  bool holdsWith(List<Entry> extra, {Entry? replacing}) {
    return _holdings.holdsWith([
      for (final e in _entries)
        if (replacing == null || e.id != replacing.id) e,
      ...extra,
    ]);
  }

  /// Rebuilds the holdings from the starting positions and every
  /// investment entry; an oversold trade throws a [StateError], or, when
  /// [lenient], as for a book just loaded, is left out of the holdings.
  void _replay({bool lenient = false}) {
    // The caller says what changed (_changed).
    _holdings.replay(_entries, lenient: lenient);
  }
}
