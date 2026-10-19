import 'dart:io';

/// Keeps the app out of screenshots, screen recordings and the
/// recent-apps preview while on. The choice is kept beside the ledger, so
/// it holds from the lock screen on.
final class ScreenPrivacy {
  ScreenPrivacy(this.directory, this._secure);

  final Directory directory;

  /// Tells the phone to hide the screens, or to stop hiding them.
  final Future<void> Function(bool on) _secure;

  File get _file => File('${directory.path}/private-screen');

  bool get on => _file.existsSync();

  /// Applies the kept choice, as at launch.
  Future<void> apply() => _secure(on);

  /// Turns hiding on or off and keeps the choice.
  Future<void> turn({required bool on}) async {
    if (on) {
      await directory.create(recursive: true);
      await _file.writeAsString('on');
    } else if (_file.existsSync()) {
      await _file.delete();
    }
    await _secure(on);
  }
}
