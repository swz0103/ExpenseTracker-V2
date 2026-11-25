import 'package:expense_tracker/src/app/when_idle.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('waits for the frame asked for, then completes', (tester) async {
    await tester.pumpWidget(const SizedBox());
    final steps = <String>[];
    // A frame is asked for before the wait: it is drawn first.
    tester.binding.scheduleFrameCallback((_) => steps.add('frame'));
    tester.binding.scheduleFrame();
    whenIdle().then((_) => steps.add('idle')).ignore();
    expect(steps, isEmpty);
    await tester.pump();
    // The idle task runs at the next turn of the event loop.
    await tester.pump(Duration.zero);
    expect(steps, ['frame', 'idle']);
  });
}
