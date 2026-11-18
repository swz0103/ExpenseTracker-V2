import 'package:expense_tracker/src/core/look/motion.dart';
import 'package:expense_tracker/src/features/entries/compose/fields_fold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _fold({required bool open, required bool quiet}) => MediaQuery(
  data: MediaQueryData(disableAnimations: quiet),
  child: MaterialApp(
    home: Scaffold(
      body: FieldsFold(
        closed: '更多',
        open: open,
        viewing: false,
        onToggle: () {},
        body: const [SizedBox(height: 200, child: Text('inside'))],
      ),
    ),
  ),
);

void main() {
  testWidgets('a duration is none while motion is turned off', (tester) async {
    late Duration on, off;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          on = Motion.of(context, const Duration(milliseconds: 180));
          return MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Builder(
              builder: (context) {
                off = Motion.of(context, const Duration(milliseconds: 180));
                return const SizedBox();
              },
            ),
          );
        },
      ),
    );
    expect(on, const Duration(milliseconds: 180));
    expect(off, Duration.zero);
  });

  testWidgets('a fold opens at once with motion off, over time with it on', (
    tester,
  ) async {
    // With motion on, a frame in the fold is still growing.
    await tester.pumpWidget(_fold(open: false, quiet: false));
    await tester.pumpWidget(_fold(open: true, quiet: false));
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.getSize(find.byType(AnimatedSize)).height, lessThan(200));
    await tester.pumpAndSettle();

    // With it off, the first frame shows it all, and no animation runs.
    await tester.pumpWidget(_fold(open: false, quiet: true));
    await tester.pumpWidget(_fold(open: true, quiet: true));
    expect(find.byType(AnimatedSize), findsNothing);
    expect(tester.getSize(find.text('inside')).height, greaterThan(0));
    expect(tester.takeException(), isNull);
  });
}
