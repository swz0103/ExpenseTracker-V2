import 'package:expense_tracker/src/app/between_frames.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a step waits for the frame asked for, then goes on', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox());
    final steps = <String>[];
    final between = BetweenFrames();
    // A frame is asked for before the wait: it is drawn first.
    tester.binding.scheduleFrameCallback((_) => steps.add('frame'));
    tester.binding.scheduleFrame();
    between.next().then((go) => steps.add('step $go')).ignore();
    expect(steps, isEmpty);
    await tester.pump();
    // The step runs at a later turn of the event loop.
    expect(steps, ['frame']);
    await tester.pump(Duration.zero);
    expect(steps, ['frame', 'step true']);
  });

  testWidgets('stopped, a step waited for and every later one is told to '
      'stop, nothing left pending', (tester) async {
    await tester.pumpWidget(const SizedBox());
    final steps = <bool>[];
    final between = BetweenFrames();
    between.next().then(steps.add).ignore();
    // No frame coming: the turn's timer is set at once, and cancelled.
    between.stop();
    await tester.idle();
    expect(steps, [false]);
    expect(await between.next(), isFalse);
  });
}
