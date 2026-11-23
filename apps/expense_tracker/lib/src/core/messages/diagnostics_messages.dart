/// The words of faults nobody foresaw: what the error log names them, and
/// the one note the person gets when one happens in a release build
/// (unhandled_errors.dart).
abstract final class DiagnosticsMessages {
  /// A fault while a screen was being built, laid out or drawn.
  static const screenError = '畫面錯誤';

  /// A fault nothing caught, outside the drawing of a screen.
  static const unforeseenError = '未預期的錯誤';

  /// A fault the Dart runtime reports for the whole isolate.
  static const isolateError = '背景執行錯誤';

  /// The error log's own file could not be read or written.
  static const logFile = '診斷紀錄';

  /// What the person is told, once, when a fault nobody foresaw happens:
  /// that it happened, and where it was kept.
  static const unforeseenNote = '發生未預期的錯誤，已記在「設定 › 關於 › 診斷」';
}
