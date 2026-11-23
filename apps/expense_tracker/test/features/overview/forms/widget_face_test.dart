import 'package:expense_tracker/src/features/overview/forms/widget_face.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/places.dart';

/// The home-screen widget as the app draws it (the preview and 設定 ›
/// 桌面小工具): the full 本月概況 card with its budget bar and week, the
/// one-row card, what each shows with no figures chosen, and that their
/// 記支出 and 記收入 open what they say.
void main() {
  setUpAll(loadFonts);

  /// What home_widget.dart keeps for 2026-10-20, a Tuesday, with a
  /// budget of 20,000 and 12,345 spent that day.
  const snapshot = <String, Object?>{
    'v': 2,
    'title': '10 月支出',
    'figure': '12,345',
    'budget': '預算 20,000',
    'detail': '剩 7,655',
    'progress': 62,
    'pace': 65,
    'week': [0, 0, 100, -1, -1, -1, -1],
    'weekTotal': '12,345',
    'today': 2,
    'shortLabel': '10 月預算剩',
    'shortFigure': '7,655',
  };

  Future<void> put(WidgetTester tester, Widget face) async {
    tester.view.physicalSize = const Size(400, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(child: SizedBox(width: 340, child: face)),
        ),
      ),
    );
  }

  /// The bars drawn for the week's days, by their height.
  List<double> bars(WidgetTester tester) => [
    for (final f in tester.widgetList<FractionallySizedBox>(
      find.byType(FractionallySizedBox),
    ))
      f.heightFactor ?? 1,
  ];

  testWidgets('the full card shows the month, the budget and this week day '
      'by day', (tester) async {
    await put(tester, const WidgetFace(snapshot: snapshot));
    expect(find.text('10 月支出'), findsOneWidget);
    expect(find.text('12,345'), findsNWidgets(2), reason: 'month and week');
    expect(find.text('預算 20,000'), findsOneWidget);
    expect(find.text('剩 7,655'), findsOneWidget);
    expect(find.text('本週'), findsOneWidget);
    // Sunday and Monday spent nothing, Tuesday is all of it, the rest to
    // come are dots with no bar.
    expect(bars(tester), [0.0, 0.0, 1.0]);
    expect(find.text('支出'), findsOneWidget);
    expect(find.text('收入'), findsOneWidget);
  });

  testWidgets('the budget bar fills to the share used, with the pace mark '
      'where the month is', (tester) async {
    await put(tester, const WidgetFace(snapshot: snapshot));
    final full = tester.getSize(find.byType(Stack).first).width;
    final filled = tester
        .widgetList<Positioned>(find.byType(Positioned))
        .firstWhere((p) => p.left == 0 && p.width != null);
    expect(filled.width, closeTo(full * 0.62, 0.01));
    final pace = tester
        .widgetList<Positioned>(find.byType(Positioned))
        .firstWhere((p) => p.width == 2);
    expect(pace.left, closeTo(full * 0.65 - 2, 0.01));
  });

  testWidgets('with no figure to show, the card says amounts are hidden '
      'and that a tap opens the app (F42)', (tester) async {
    await put(tester, const WidgetFace(snapshot: null));
    expect(find.text('記帳本'), findsOneWidget);
    expect(find.text('已隱藏金額'), findsOneWidget);
    expect(find.text('點此開啟'), findsOneWidget);
    expect(find.text('本週'), findsNothing, reason: 'no week kept');
    expect(find.byType(Positioned), findsNothing, reason: 'no budget bar');
  });

  testWidgets('記支出, 記收入 and the card itself each open what they say', (
    tester,
  ) async {
    final opened = <String>[];
    await put(
      tester,
      WidgetFace(
        snapshot: snapshot,
        onOpen: () => opened.add('app'),
        onExpense: () => opened.add('expense'),
        onIncome: () => opened.add('income'),
      ),
    );
    final semantics = tester.ensureSemantics();
    await tester.tap(find.bySemanticsLabel('記支出'));
    await tester.tap(find.bySemanticsLabel('記收入'));
    await tester.tap(find.byType(GestureDetector).first);
    expect(opened, ['expense', 'income', 'app']);
    semantics.dispose();
  });

  testWidgets('without callbacks the halves are a picture, not buttons', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await put(tester, const WidgetFace(snapshot: snapshot));
    final node = tester.getSemantics(find.bySemanticsLabel('記支出'));
    expect(node.getSemanticsData().flagsCollection.isButton, isFalse);
    semantics.dispose();
  });

  testWidgets('the one-row card shows what is left over its bar, with round '
      '− and ＋', (tester) async {
    final opened = <String>[];
    await put(
      tester,
      WidgetRow(
        snapshot: snapshot,
        onOpen: () => opened.add('app'),
        onExpense: () => opened.add('expense'),
        onIncome: () => opened.add('income'),
      ),
    );
    expect(find.text('10 月預算剩'), findsOneWidget);
    expect(find.text('7,655'), findsOneWidget);
    expect(find.text('10 月支出'), findsNothing);
    final semantics = tester.ensureSemantics();
    await tester.tap(find.bySemanticsLabel('記收入'));
    await tester.tap(find.bySemanticsLabel('記支出'));
    await tester.tap(find.byType(GestureDetector).first);
    expect(opened, ['income', 'expense', 'app']);
    semantics.dispose();
  });

  testWidgets('the one-row card falls back to the title and figure, and '
      'to the empty card with nothing kept', (tester) async {
    await put(
      tester,
      const WidgetRow(snapshot: {'title': '10 月支出', 'figure': '已用 62%'}),
    );
    expect(find.text('10 月支出'), findsOneWidget);
    expect(find.text('已用 62%'), findsOneWidget);

    // One row high: the same two lines, and the two buttons as ever.
    await put(tester, const WidgetRow(snapshot: null));
    expect(find.text('已隱藏金額'), findsOneWidget);
    expect(find.text('點此開啟'), findsOneWidget);
    expect(find.text('−'), findsOneWidget);
    expect(find.text('＋'), findsOneWidget);
  });
}
