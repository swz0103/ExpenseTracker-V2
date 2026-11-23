import 'dart:io';

/// Keeps the app out of screenshots, screen recordings and the
/// recent-apps preview: always while no ledger is open (the lock screen
/// and what is typed on it, [showing]), and over the open ledger while
/// the person's choice 禁止截圖 is on. The choice is kept beside the
/// ledger, so it holds from the lock screen on.
final class ScreenPrivacy {
  ScreenPrivacy(Directory this.directory, this._secure);

  /// Kept in memory only, as in the web preview, where nothing is hidden.
  ScreenPrivacy.inMemory()
    : directory = null,
      _secure = _nothing,
      _kept = false;

  static Future<void> _nothing(bool on) async {}

  final Directory? directory;

  /// The choice in memory, for [ScreenPrivacy.inMemory].
  bool? _kept;

  /// Tells the phone to hide the screens, or to stop hiding them.
  final Future<void> Function(bool on) _secure;

  File get _file => File('${directory!.path}/private-screen');

  /// The person's choice: the open ledger is hidden too.
  bool get on => _kept ?? _file.existsSync();

  /// No ledger is open, as far as this was told: so at launch, until
  /// [showing] says one is.
  var _locked = true;

  /// Whether the phone hides the screens now.
  bool get hiding => on || _locked;

  /// Applies what holds now, as at launch.
  Future<void> apply() => _secure(hiding);

  /// The lock screen is up ([locked]) or a ledger is open.
  Future<void> showing({required bool locked}) {
    _locked = locked;
    return apply();
  }

  /// Turns hiding the open ledger on or off and keeps the choice.
  Future<void> turn({required bool on}) async {
    if (_kept != null) {
      _kept = on;
    } else if (on) {
      await directory!.create(recursive: true);
      await _file.writeAsString('on');
    } else if (_file.existsSync()) {
      await _file.delete();
    }
    await apply();
  }
}
