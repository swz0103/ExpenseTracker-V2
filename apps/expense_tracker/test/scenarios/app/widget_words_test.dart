import 'dart:io';

import 'package:expense_tracker/src/core/messages/widget_messages.dart';
import 'package:flutter_test/flutter_test.dart';

/// The home-screen widget with no figure to show is drawn by Android from
/// its own words (`NativeWords.kt`, read by `WidgetView` in
/// SummaryWidget.kt: there is no snapshot to read then), and the app draws
/// pictures of it from `core/messages/widget_messages.dart`. The two
/// cannot share a file, so this holds them to the same words (F42). The
/// words once the month is over go in the snapshot; Android keeps them
/// too for a snapshot written before they did.
void main() {
  const folder =
      'android/app/src/main/kotlin/io/github/swz0103/expensetracker/';
  final kotlin = File('${folder}SummaryWidget.kt').readAsStringSync();
  final words = File('${folder}NativeWords.kt').readAsStringSync();

  /// The value of the Kotlin constant [name].
  String constant(String name) {
    final match = RegExp('const val $name = "([^"]*)"').firstMatch(words);
    expect(match, isNotNull, reason: '$name is not in NativeWords.kt');
    return match![1]!;
  }

  test('the words are the ones a person reads on the home screen', () {
    expect(WidgetWords.hiddenTitle, '記帳本');
    expect(WidgetWords.hidden, '已隱藏金額');
    expect(WidgetWords.hiddenOpen, '點此打開');
  });

  test('Android draws the widget with the app\'s words', () {
    expect(constant('WIDGET_HIDDEN_TITLE'), WidgetWords.hiddenTitle);
    expect(constant('WIDGET_HIDDEN'), WidgetWords.hidden);
    expect(constant('WIDGET_HIDDEN_OPEN'), WidgetWords.hiddenOpen);
    expect(constant('WIDGET_STALE_TITLE'), WidgetWords.staleTitle);
    expect(constant('WIDGET_STALE_FIGURE'), WidgetWords.staleFigure);
    expect(constant('WIDGET_STALE_DETAIL'), WidgetWords.staleDetail);
  });

  test('once the month is over it says to open the app', () {
    expect(widgetStaleFace, {
      'title': '本月概況',
      'figure': '—',
      'detail': '打開 App 更新本月數字',
    });
  });

  test('and lays them out as the app\'s pictures of it do', () {
    expect(hiddenWidgetFace, {
      'title': '記帳本',
      'figure': '已隱藏金額',
      'detail': '點此打開',
      'shortLabel': '已隱藏金額',
      'shortFigure': '點此打開',
    });
    // Shown(title, figure, detail, progress, shortLabel, shortFigure).
    expect(
      kotlin,
      contains(
        'NativeWords.WIDGET_HIDDEN_TITLE, NativeWords.WIDGET_HIDDEN, '
        'NativeWords.WIDGET_HIDDEN_OPEN, null,\n'
        '                shortLabel = NativeWords.WIDGET_HIDDEN, '
        'shortFigure = NativeWords.WIDGET_HIDDEN_OPEN,',
      ),
    );
  });
}
