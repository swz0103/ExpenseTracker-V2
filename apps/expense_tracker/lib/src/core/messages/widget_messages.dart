/// The words of the home-screen widget while it shows no figure of the
/// ledger: none was chosen in 設定 › 外觀 › 桌面小工具, or amounts are
/// hidden in the app. It says so and that a tap opens the app, so it
/// reads as meant, not as broken; its 支出 and 收入 buttons work as ever.
///
/// The widget itself draws these from `WidgetView.of(null, …)` in
/// `SummaryWidget.kt`, which has no snapshot to read then (nothing of the
/// ledger is written to disk); a test holds the two to the same words
/// (test/scenarios/app/widget_words_test.dart).
abstract final class WidgetWords {
  static const hiddenTitle = '記帳本';
  static const hidden = '已隱藏金額';
  static const hiddenOpen = '點此開啟';
}

/// The widget's face with no figure, in the snapshot's own fields, for
/// the pictures of it the app draws.
const hiddenWidgetFace = <String, Object?>{
  'title': WidgetWords.hiddenTitle,
  'figure': WidgetWords.hidden,
  'detail': WidgetWords.hiddenOpen,
  'shortLabel': WidgetWords.hidden,
  'shortFigure': WidgetWords.hiddenOpen,
};
