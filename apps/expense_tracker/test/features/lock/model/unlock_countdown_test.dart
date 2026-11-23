import 'package:expense_tracker/src/core/diagnostics/error_log.dart';
import 'package:expense_tracker/src/features/lock/model/unlock_countdown.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// A countdown over a wait the test sets, and what it was told.
  ({
    UnlockCountdown countdown,
    List<Duration> told,
    void Function(Duration) set,
  })
  make({bool Function()? limited, bool fails = false}) {
    var wait = Duration.zero;
    final told = <Duration>[];
    final countdown = UnlockCountdown(
      ask: () async {
        if (fails) throw StateError('unreadable');
        return wait;
      },
      limited: limited ?? () => true,
      changed: told.add,
    );
    return (countdown: countdown, told: told, set: (d) => wait = d);
  }

  testWidgets('no wait: nothing is told and the wait stays zero', (
    tester,
  ) async {
    final c = make();
    await c.countdown.refresh();
    expect(c.told, isEmpty);
    expect(c.countdown.wait, Duration.zero);
    c.countdown.close();
  });

  testWidgets('a wait is told, asked again each second, and its end told', (
    tester,
  ) async {
    final c = make();
    c.set(const Duration(seconds: 30));
    await c.countdown.refresh();
    expect(c.told, [const Duration(seconds: 30)]);
    expect(c.countdown.wait, const Duration(seconds: 30));

    // A second later the keeper says 29 s: asked by the ticker.
    c.set(const Duration(seconds: 29));
    await tester.pump(const Duration(seconds: 1));
    expect(c.countdown.wait, const Duration(seconds: 29));

    // Over: zero is told once, and the ticker stops asking.
    c.set(Duration.zero);
    await tester.pump(const Duration(seconds: 1));
    expect(c.told, [
      const Duration(seconds: 30),
      const Duration(seconds: 29),
      Duration.zero,
    ]);
    await tester.pump(const Duration(seconds: 3));
    expect(c.told, hasLength(3));
    c.countdown.close();
  });

  testWidgets('a secret not limited (a backup\'s) asks nothing', (
    tester,
  ) async {
    final c = make(limited: () => false);
    c.set(const Duration(seconds: 30));
    await c.countdown.refresh();
    expect(c.told, isEmpty);
    expect(c.countdown.wait, Duration.zero);
    c.countdown.close();
  });

  testWidgets('closed, it neither asks nor tells', (tester) async {
    final c = make();
    c.set(const Duration(seconds: 30));
    await c.countdown.refresh();
    c.countdown.close();
    c.set(const Duration(seconds: 10));
    await tester.pump(const Duration(seconds: 2));
    await c.countdown.refresh();
    expect(c.told, [const Duration(seconds: 30)]);
  });

  testWidgets('a keeper that cannot say is noted, and no wait is made up', (
    tester,
  ) async {
    final c = make(fails: true);
    await c.countdown.refresh();
    expect(c.told, isEmpty);
    expect(ErrorLog.instance.entries.first.$2, contains('上鎖'));
    c.countdown.close();
  });
}
