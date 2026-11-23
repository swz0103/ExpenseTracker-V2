import 'dart:io';

import 'package:expense_tracker/src/core/platform/unlock_attempts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vault/backup_security.dart';

/// Wrong tries on the lock screen are counted in a file beside the
/// keyring and slowed down by the vault's table, with clocks the test
/// sets: no test here waits.
void main() {
  late Directory directory;
  late File file;

  /// The wall clock, as the phone shows it; a test moves it.
  late DateTime wall;

  /// The phone's uptime; null where there is no such clock.
  Uptime? uptime;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('attempts-');
    file = File('${directory.path}/unlock-attempts.json');
    wall = DateTime.utc(2026, 11, 23, 9);
    uptime = null;
  });

  tearDown(() => directory.deleteSync(recursive: true));

  /// The count as a new start of the app reads it from the file.
  UnlockAttempts attempts({bool withUptime = false}) => UnlockAttempts(
    file,
    now: () => wall,
    uptime: withUptime ? () async => uptime : null,
  );

  Future<void> fail(UnlockAttempts a, int times) async {
    for (var i = 0; i < times; i++) {
      await a.failed();
    }
  }

  test('four wrong tries cost nothing; the fifth waits 30 seconds', () async {
    final a = attempts();
    await fail(a, 4);
    expect(a.failures, 4);
    expect(await a.wait(), Duration.zero);
    expect(await a.failed(), const Duration(seconds: 30));
    expect(await a.wait(), const Duration(seconds: 30));
  });

  test('the wait counts down with the clock and ends', () async {
    final a = attempts();
    await fail(a, 5);
    wall = wall.add(const Duration(seconds: 12));
    // 30 s - 12 s
    expect(await a.wait(), const Duration(seconds: 18));
    wall = wall.add(const Duration(seconds: 18));
    expect(await a.wait(), Duration.zero);
    wall = wall.add(const Duration(days: 3));
    expect(await a.wait(), Duration.zero);
  });

  test(
    'each further wrong try waits longer, by the table, an hour at most',
    () async {
      final a = attempts();
      await fail(a, 5);
      expect(await a.failed(), const Duration(minutes: 1));
      expect(await a.failed(), const Duration(minutes: 2));
      expect(await a.failed(), const Duration(minutes: 5));
      expect(await a.failed(), const Duration(minutes: 15));
      expect(await a.failed(), const Duration(minutes: 30));
      expect(await a.failed(), const Duration(hours: 1));
      expect(await a.failed(), const Duration(hours: 1));
      expect(a.failures, 12);
    },
  );

  test('closing the app keeps the count and the wait', () async {
    await fail(attempts(), 6);
    wall = wall.add(const Duration(seconds: 20));
    final again = attempts();
    expect(again.failures, 6);
    // 60 s - 20 s
    expect(await again.wait(), const Duration(seconds: 40));
  });

  test('opening the ledger starts the count again', () async {
    final a = attempts();
    await fail(a, 7);
    a.clear();
    expect(a.failures, 0);
    expect(await a.wait(), Duration.zero);
    expect(file.existsSync(), isFalse);
    expect(attempts().failures, 0);
    // The four free tries are free again.
    await fail(a, 4);
    expect(await a.wait(), Duration.zero);
  });

  test('a clock set back does not shorten the wait: the whole wait starts '
      'again, and is not made longer than that', () async {
    final a = attempts();
    await fail(a, 6);
    wall = wall.add(const Duration(seconds: 50));
    // 60 s - 50 s
    expect(await a.wait(), const Duration(seconds: 10));
    // Set back a day: not 10 s, and not a day either, but the minute.
    wall = wall.subtract(const Duration(days: 1));
    expect(await a.wait(), const Duration(minutes: 1));
    wall = wall.add(const Duration(seconds: 25));
    // 60 s - 25 s
    expect(await a.wait(), const Duration(seconds: 35));
    // Set back again: the whole minute again.
    wall = wall.subtract(const Duration(hours: 2));
    expect(await a.wait(), const Duration(minutes: 1));
    wall = wall.add(const Duration(minutes: 1));
    expect(await a.wait(), Duration.zero);
  });

  test('a clock set back keeps the wait after the app is closed too', () async {
    await fail(attempts(), 6);
    wall = wall.subtract(const Duration(days: 30));
    expect(await attempts().wait(), const Duration(minutes: 1));
    wall = wall.add(const Duration(seconds: 59));
    expect(await attempts().wait(), const Duration(seconds: 1));
  });

  group('with the phone\'s uptime', () {
    test('the wait runs by uptime, whatever the clock is set to', () async {
      uptime = (boot: 'boot-7', up: const Duration(hours: 2));
      final a = attempts(withUptime: true);
      await fail(a, 8);
      expect(await a.wait(), const Duration(minutes: 5));
      // The clock set a day ahead: nothing gained.
      wall = wall.add(const Duration(days: 1));
      expect(await a.wait(), const Duration(minutes: 5));
      // Set a week back: nothing lost either.
      wall = wall.subtract(const Duration(days: 8));
      uptime = (boot: 'boot-7', up: const Duration(hours: 2, minutes: 3));
      // 5 min - 3 min
      expect(await a.wait(), const Duration(minutes: 2));
      uptime = (boot: 'boot-7', up: const Duration(hours: 2, minutes: 5));
      expect(await a.wait(), Duration.zero);
    });

    test('closing the app does not lose it', () async {
      uptime = (boot: 'boot-7', up: const Duration(hours: 2));
      await fail(attempts(withUptime: true), 8);
      wall = wall.add(const Duration(days: 1));
      uptime = (boot: 'boot-7', up: const Duration(hours: 2, minutes: 4));
      // 5 min - 4 min, though the clock says a day went by.
      expect(
        await attempts(withUptime: true).wait(),
        const Duration(minutes: 1),
      );
    });

    test('after the phone restarts the wall clock is used, and the wait is '
        'measured in the new start from then on', () async {
      uptime = (boot: 'boot-7', up: const Duration(hours: 2));
      await fail(attempts(withUptime: true), 8);
      // Restarted: two minutes later by the clock.
      wall = wall.add(const Duration(minutes: 2));
      uptime = (boot: 'boot-8', up: const Duration(seconds: 40));
      final a = attempts(withUptime: true);
      // 5 min - 2 min
      expect(await a.wait(), const Duration(minutes: 3));
      // From here by uptime: the clock set ahead gains nothing.
      wall = wall.add(const Duration(days: 1));
      uptime = (boot: 'boot-8', up: const Duration(seconds: 100));
      // 3 min - 60 s
      expect(await a.wait(), const Duration(minutes: 2));
    });

    test(
      'a phone that does not say its uptime goes by the wall clock',
      () async {
        final a = UnlockAttempts(
          file,
          now: () => wall,
          uptime: () async => throw StateError('no channel'),
        );
        await fail(a, 5);
        wall = wall.add(const Duration(seconds: 10));
        // 30 s - 10 s
        expect(await a.wait(), const Duration(seconds: 20));
      },
    );
  });

  test('a table of its own is followed', () async {
    final a = UnlockAttempts(
      file,
      now: () => wall,
      policy: const AttemptPolicy([
        AttemptStep(failures: 1, wait: Duration(seconds: 7)),
      ]),
    );
    expect(await a.failed(), const Duration(seconds: 7));
    expect(await a.wait(), const Duration(seconds: 7));
  });

  test('a file that cannot be read counts as none', () async {
    file.writeAsStringSync('not json');
    final a = attempts();
    expect(a.failures, 0);
    expect(await a.wait(), Duration.zero);
  });
}
