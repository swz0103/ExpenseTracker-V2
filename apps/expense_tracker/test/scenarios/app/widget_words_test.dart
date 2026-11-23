import 'dart:io';

import 'package:expense_tracker/src/core/messages/widget_messages.dart';
import 'package:flutter_test/flutter_test.dart';

/// The home-screen widget with no figure to show is drawn by Android from
/// its own words (`WidgetView` in SummaryWidget.kt: there is no snapshot
/// to read then), and the app draws pictures of it from
/// `core/messages/widget_messages.dart`. The two cannot share a file, so
/// this holds them to the same words (F42).
void main() {
  final kotlin = File(
    'android/app/src/main/kotlin/io/github/swz0103/expensetracker/'
    'SummaryWidget.kt',
  ).readAsStringSync();

  /// The value of the Kotlin constant [name].
  String constant(String name) {
    final match = RegExp('const val $name = "([^"]*)"').firstMatch(kotlin);
    expect(match, isNotNull, reason: '$name is not in SummaryWidget.kt');
    return match![1]!;
  }

  test('the words are the ones a person reads on the home screen', () {
    expect(WidgetWords.hiddenTitle, '記帳本');
    expect(WidgetWords.hidden, '已隱藏金額');
    expect(WidgetWords.hiddenOpen, '點此開啟');
  });

  test('Android draws the widget with the app\'s words', () {
    expect(constant('HIDDEN_TITLE'), WidgetWords.hiddenTitle);
    expect(constant('HIDDEN'), WidgetWords.hidden);
    expect(constant('HIDDEN_OPEN'), WidgetWords.hiddenOpen);
  });

  test('and lays them out as the app\'s pictures of it do', () {
    expect(hiddenWidgetFace, {
      'title': '記帳本',
      'figure': '已隱藏金額',
      'detail': '點此開啟',
      'shortLabel': '已隱藏金額',
      'shortFigure': '點此開啟',
    });
    // Shown(title, figure, detail, progress, shortLabel, shortFigure).
    expect(
      kotlin,
      contains(
        'HIDDEN_TITLE, HIDDEN, HIDDEN_OPEN, null,\n'
        '                shortLabel = HIDDEN, shortFigure = HIDDEN_OPEN,',
      ),
    );
  });
}
