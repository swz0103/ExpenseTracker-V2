/// Trips out of the app that the app itself sends the person on and waits
/// for: the camera for a receipt, a file chooser, the save dialog, Google's
/// sign-in. The lock gate asks whether one is under way when the app
/// leaves the screen, so a short auto-lock does not close the form the
/// trip was made for (`AutoLock.errand`).
abstract final class Errands {
  static var _under = 0;

  /// Whether a trip the app started is under way.
  static bool get any => _under > 0;

  /// Runs [trip], which shows another app's screen and completes when the
  /// person is back from it.
  static Future<T> run<T>(Future<T> Function() trip) async {
    _under++;
    try {
      return await trip();
    } finally {
      _under--;
    }
  }
}
