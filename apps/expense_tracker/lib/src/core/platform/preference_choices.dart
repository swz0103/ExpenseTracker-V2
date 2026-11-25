/// Light or dark colours.
enum Appearance {
  system('跟著手機'),
  light('淺色'),
  dark('深色');

  const Appearance(this.label);

  final String label;
}

/// 震動: none, Android's light ticks, or a step heavier (標準).
enum Vibration {
  off('關'),
  light('輕'),
  standard('標準');

  const Vibration(this.label);

  final String label;
}

/// What the home-screen widget 本月概況 shows: nothing of the ledger, the
/// month's spending and what is left of the budget, or only the share of
/// the budget used.
enum WidgetFigures {
  off('不顯示數字'),
  amounts('顯示金額'),
  percent('只顯示百分比');

  const WidgetFigures(this.label);

  final String label;
}

/// 自動上鎖: how long the app may be off the screen before a ledger with a
/// password asks for it again. The one table of the choices; [standard]
/// until the person picks another.
enum AutoLock {
  immediately('立即', Duration.zero),
  oneMinute('1 分鐘', Duration(minutes: 1)),
  fiveMinutes('5 分鐘', Duration(minutes: 5)),
  fifteenMinutes('15 分鐘', Duration(minutes: 15)),
  never('不自動上鎖', null);

  const AutoLock(this.label, this.after);

  final String label;

  /// How long away locks the ledger; null for never while the app stays
  /// open (a closed app always asks again).
  final Duration? after;

  /// The choice a ledger has until another is made.
  static const standard = fiveMinutes;

  /// The least time away that locks the ledger while the app itself sent
  /// the person elsewhere for a moment (the camera for a receipt, a file
  /// chooser, Google's sign-in), so a shorter choice does not close the
  /// form being filled in.
  static const errand = Duration(minutes: 5);

  /// How long away locks the ledger under this choice; [onErrand] when
  /// the app itself sent the person away. Null for never.
  Duration? limit({required bool onErrand}) {
    final after = this.after;
    if (after == null) return null;
    return onErrand && after < errand ? errand : after;
  }
}
