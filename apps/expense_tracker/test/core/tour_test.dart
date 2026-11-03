import 'package:expense_tracker/src/core/look/glyphs.dart';
import 'package:expense_tracker/src/core/ui/tour.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final top = GlobalKey();
  final bottom = GlobalKey();
  var done = 0;

  Future<void> show(WidgetTester tester) async {
    done = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned(
                left: 20,
                top: 40,
                child: SizedBox(key: top, width: 60, height: 40),
              ),
              Positioned(
                right: 20,
                bottom: 40,
                child: SizedBox(key: bottom, width: 50, height: 50),
              ),
              Positioned.fill(
                child: Tour(
                  onDone: () => done++,
                  stops: [
                    TourStop(
                      target: top,
                      glyph: Glyph.add,
                      title: '第一站',
                      detail: '說明',
                    ),
                    TourStop(
                      target: bottom,
                      round: true,
                      glyph: Glyph.safe,
                      title: '第二站',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    // The tour waits for the page under it to come in.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
  }

  testWidgets('the tour lights each stop in turn and ends with the tick', (
    tester,
  ) async {
    await show(tester);
    expect(find.text('第一站'), findsOneWidget);
    expect(find.text('說明'), findsOneWidget);
    // Under a light in the upper half of the screen.
    expect(
      tester.getTopLeft(find.text('第一站')).dy,
      greaterThan(tester.getBottomLeft(find.byKey(top)).dy),
    );

    await tester.tap(find.byTooltip('下一步'));
    await tester.pumpAndSettle();
    expect(find.text('第二站'), findsOneWidget);
    expect(find.byTooltip('下一步'), findsNothing, reason: 'the last stop');
    // Above a light in the lower half.
    expect(
      tester.getBottomLeft(find.byTooltip('開始')).dy,
      lessThan(tester.getTopLeft(find.byKey(bottom)).dy),
    );

    await tester.tap(find.byTooltip('開始'));
    await tester.pumpAndSettle();
    expect(done, 1);
  });

  testWidgets('a tap on the dim ends the tour at once', (tester) async {
    await show(tester);
    await tester.tapAt(const Offset(300, 300));
    await tester.pumpAndSettle();
    expect(done, 1);
  });

  testWidgets('a tap on the card itself does not end it', (tester) async {
    await show(tester);
    await tester.tap(find.text('第一站'));
    await tester.pumpAndSettle();
    expect(done, 0);
    expect(find.text('第一站'), findsOneWidget);
  });
}
