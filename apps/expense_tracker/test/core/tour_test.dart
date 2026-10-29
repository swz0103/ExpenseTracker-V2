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
                    TourStop(target: top, title: '第一站', detail: '上面'),
                    TourStop(
                      target: bottom,
                      round: true,
                      title: '第二站',
                      detail: '下面',
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

  testWidgets('the tour lights each stop in turn and ends with 開始', (
    tester,
  ) async {
    await show(tester);
    expect(find.text('第一站'), findsOneWidget);
    // Under a light in the upper half of the screen.
    expect(
      tester.getTopLeft(find.text('第一站')).dy,
      greaterThan(tester.getBottomLeft(find.byKey(top)).dy),
    );

    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    expect(find.text('第二站'), findsOneWidget);
    expect(find.text('略過'), findsNothing, reason: 'the last stop');
    // Above a light in the lower half.
    expect(
      tester.getBottomLeft(find.text('開始')).dy,
      lessThan(tester.getTopLeft(find.byKey(bottom)).dy),
    );

    await tester.tap(find.text('開始'));
    await tester.pumpAndSettle();
    expect(done, 1);
  });

  testWidgets('略過 ends the tour at once', (tester) async {
    await show(tester);
    await tester.tap(find.text('略過'));
    await tester.pumpAndSettle();
    expect(done, 1);
  });
}
