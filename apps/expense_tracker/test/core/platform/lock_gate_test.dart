import 'dart:io';

import 'package:expense_tracker/src/core/navigation/nav.dart';
import 'package:expense_tracker/src/core/platform/away_clock.dart';
import 'package:expense_tracker/src/core/platform/lock_gate.dart';
import 'package:expense_tracker/src/core/platform/preferences.dart';
import 'package:expense_tracker/src/core/platform/quick_action.dart';
import 'package:expense_tracker/src/core/platform/startup.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vault/backup_security.dart';
import 'package:vault/ledger_vault.dart';

const _password = 'correct horse battery';

/// The one gate above every screen, on a real encrypted ledger, with a
/// clock the test moves: no test here waits.
void main() {
  late Directory directory;
  late Startup startup;

  /// The person's auto-lock choice.
  late AutoLock choice;

  /// Time that only runs forward, as the away clock reads it.
  late Duration running;

  /// Whether the app itself sent the person away.
  late bool errand;

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('lock-gate-');
    startup = Startup(
      LedgerVault(
        directory,
        codec: KeyringCodec(kdf: PasswordKdf.insecureForTests),
      ),
    );
    choice = AutoLock.standard;
    running = Duration.zero;
    errand = false;
  });

  tearDown(() {
    if (startup.state is Ready) startup.lock();
    directory.deleteSync(recursive: true);
  });

  LockGate<AppRoute> gate() => LockGate<AppRoute>(
    startup,
    autoLock: () => choice,
    clock: AwayClock(running: () => running),
    onErrand: () => errand,
  );

  /// Away for [time], then back; whether the gate locked.
  bool away(LockGate<AppRoute> gate, Duration time) {
    gate.left();
    running += time;
    return gate.returned();
  }

  group('sessions (SEC-05)', () {
    test('each opening of the ledger is a session; locking ends it', () async {
      final g = gate();
      var told = 0;
      g.addListener(() => told++);
      final closed = g.session;
      expect(g.generation, 0);
      await startup.setUp(_password);
      expect(g.generation, 1);
      expect(g.session, same((startup.state as Ready).vault));
      startup.lock();
      expect(g.generation, 2);
      expect(g.session, isNot(closed), reason: 'locked, not waiting to start');
      expect(told, 2);
    });

    test(
      'a lock from anywhere is followed: the gate listens to the keys',
      () async {
        await startup.setUp(_password);
        final g = gate();
        startup.lockToRestore();
        expect(g.generation, 1);
        await startup.cancelRestore();
        expect(g.generation, 2);
      },
    );

    test('new keys open the ledger afresh: a new session', () async {
      await startup.setUp(_password);
      final g = gate();
      final before = g.session;
      await startup.resetKeys(password: _password);
      expect(g.generation, 1);
      expect(g.session, isNot(same(before)));
    });

    test('a change that keeps the ledger open keeps the session', () async {
      await startup.setUpWithoutPassword();
      final g = gate();
      // Told to the screens, but nothing closed.
      startup.notifyListeners();
      expect(g.generation, 0);
    });

    test('a gate let go stops listening', () async {
      final g = gate()..dispose();
      await startup.setUp(_password);
      expect(g.generation, 0);
    });
  });

  group('auto-lock (SEC-07)', () {
    setUp(() => startup.setUp(_password));

    test('by default, back within five minutes the ledger stays open', () {
      final g = gate();
      expect(away(g, const Duration(minutes: 4, seconds: 59)), isFalse);
      expect(startup.state, isA<Ready>());
      expect(g.covered, isFalse);
    });

    test('by default, back after five minutes the ledger locks', () async {
      final g = gate();
      expect(away(g, const Duration(minutes: 5)), isTrue);
      await pumpEventQueue();
      expect(startup.state, isA<Locked>());
    });

    test('each choice locks after its own time', () async {
      // The longest time away that keeps the ledger open, and the
      // shortest that locks it, for each choice.
      const cases = [
        (AutoLock.oneMinute, Duration(seconds: 59), Duration(minutes: 1)),
        (
          AutoLock.fiveMinutes,
          Duration(minutes: 4, seconds: 59),
          Duration(minutes: 5),
        ),
        (
          AutoLock.fifteenMinutes,
          Duration(minutes: 14, seconds: 59),
          Duration(minutes: 15),
        ),
      ];
      for (final (picked, stays, locks) in cases) {
        choice = picked;
        final g = gate();
        expect(away(g, stays), isFalse, reason: '${picked.name} stays');
        expect(startup.state, isA<Ready>());
        expect(away(g, locks), isTrue, reason: '${picked.name} locks');
        await pumpEventQueue();
        expect(startup.state, isA<Locked>());
        g.dispose();
        await startup.unlockWithPassword(_password);
      }
    });

    test('立即 locks on any trip away, however short', () async {
      choice = AutoLock.immediately;
      final g = gate();
      expect(away(g, Duration.zero), isTrue);
      await pumpEventQueue();
      expect(startup.state, isA<Locked>());
    });

    test('不自動上鎖 never locks while the app stays open', () {
      choice = AutoLock.never;
      final g = gate();
      expect(away(g, const Duration(days: 3)), isFalse);
      expect(startup.state, isA<Ready>());
      // The clock started afresh: a change of mind counts from the next
      // trip away.
      choice = AutoLock.oneMinute;
      expect(away(g, const Duration(seconds: 30)), isFalse);
    });

    test('the choice is read when the app comes back', () async {
      final g = gate();
      g.left();
      running += const Duration(minutes: 2);
      choice = AutoLock.oneMinute;
      expect(g.returned(), isTrue);
      await pumpEventQueue();
      expect(startup.state, isA<Locked>());
    });

    test('a trip the app itself sent the person on does not lock within '
        'five minutes, whatever shorter time is chosen', () async {
      choice = AutoLock.immediately;
      final g = gate();
      errand = true;
      expect(away(g, const Duration(minutes: 4, seconds: 59)), isFalse);
      expect(startup.state, isA<Ready>());
      expect(away(g, const Duration(minutes: 5)), isTrue);
      await pumpEventQueue();
      expect(startup.state, isA<Locked>());
    });

    test('a longer choice is not shortened by such a trip', () {
      choice = AutoLock.fifteenMinutes;
      final g = gate();
      errand = true;
      expect(away(g, const Duration(minutes: 14)), isFalse);
      expect(startup.state, isA<Ready>());
    });

    test('several leavings count as one trip, from the first', () async {
      choice = AutoLock.oneMinute;
      final g = gate();
      g.left();
      running += const Duration(seconds: 50);
      g.left();
      running += const Duration(seconds: 10);
      expect(g.returned(), isTrue);
      expect(g.returned(), isFalse, reason: 'already back');
      await pumpEventQueue();
    });

    test('coming back without having left decides nothing', () {
      final g = gate();
      expect(g.returned(), isFalse);
      expect(startup.state, isA<Ready>());
    });
  });

  test('a ledger without a password never locks or covers', () async {
    await startup.setUpWithoutPassword();
    choice = AutoLock.immediately;
    final g = gate();
    g.left();
    expect(g.covered, isFalse);
    running += const Duration(hours: 1);
    expect(g.returned(), isFalse);
    expect(startup.state, isA<Ready>());
  });

  group('the cover', () {
    setUp(() => startup.setUp(_password));

    test('off the screen the ledger is covered at once, and shown again '
        'when back in time', () {
      final g = gate();
      var told = 0;
      g.addListener(() => told++);
      expect(g.covered, isFalse);
      g.left();
      expect(g.covered, isTrue);
      expect(told, 1);
      running += const Duration(minutes: 1);
      expect(g.returned(), isFalse);
      expect(g.covered, isFalse);
      expect(told, 2);
    });

    test('with 不自動上鎖 nothing is covered: it will not lock', () {
      choice = AutoLock.never;
      final g = gate()..left();
      expect(g.covered, isFalse);
    });

    test('back too late, the ledger stays covered while what is being '
        'written is kept, then it closes', () async {
      final g = gate();
      final steps = <String>[];
      Future<void> lock() async {
        steps.add('covered ${g.covered}, closing ${g.closing}');
        await Future<void>.delayed(Duration.zero);
        steps.add('open ${startup.state is Ready}');
        startup.lock();
      }

      g.attach(lock);
      expect(away(g, const Duration(minutes: 5)), isTrue);
      // Decided at once, before anything is drawn.
      expect(g.covered, isTrue);
      expect(g.closing, isTrue);
      expect(startup.state, isA<Ready>(), reason: 'still being kept');
      await pumpEventQueue();
      expect(steps, ['covered true, closing true', 'open true']);
      expect(startup.state, isA<Locked>());
      expect(g.closing, isFalse);
      expect(g.covered, isFalse, reason: 'the lock screen shows');
    });

    test(
      'a failure to keep what is being written still closes the ledger',
      () async {
        final g = gate();
        g.attach(() async => throw StateError('disk full'));
        await g.lock();
        expect(startup.state, isA<Locked>());
      },
    );

    test('a session that went away no longer locks for the gate', () async {
      final g = gate();
      var asked = 0;
      Future<void> lock() async => asked++;
      Future<void> other() async {}
      g.attach(lock);
      g.detach(other);
      await g.lock();
      expect(asked, 1);
      await startup.unlockWithPassword(_password);
      g.attach(lock);
      g.detach(lock);
      await g.lock();
      expect(asked, 1);
      expect(startup.state, isA<Locked>());
    });

    test('locking twice at once closes once', () async {
      final g = gate();
      var asked = 0;
      g.attach(() async {
        asked++;
        await Future<void>.delayed(Duration.zero);
      });
      final first = g.lock();
      final second = g.lock();
      await Future.wait([first, second]);
      expect(asked, 1);
      expect(startup.state, isA<Locked>());
    });

    test('locking a ledger already locked does nothing', () async {
      startup.lock();
      final g = gate();
      await g.lock();
      expect(g.generation, 0);
    });
  });

  group('ways in (F43)', () {
    test('an action asked for while locked waits for the unlock, then '
        'reaches the screens once', () async {
      await startup.setUp(_password);
      startup.lock();
      final g = gate();
      g.ask(QuickAction.expense);
      expect(g.quick.value, isNull, reason: 'nothing opens over the lock');
      await startup.unlockWithPassword(_password);
      expect(g.quick.value, QuickAction.expense);
      // The screen acts on it and sets it back.
      g.quick.value = null;
      startup.lock();
      await startup.unlockWithPassword(_password);
      expect(g.quick.value, isNull, reason: 'acted on once');
    });

    test(
      'with the ledger open and in front it reaches the screens at once',
      () async {
        await startup.setUp(_password);
        final g = gate();
        g.ask(QuickAction.income);
        expect(g.quick.value, QuickAction.income);
      },
    );

    test('asked for while the app is behind, it waits for the decision on '
        'coming back: kept through a lock, never opened on a ledger about '
        'to close', () async {
      await startup.setUp(_password);
      final g = gate();
      g.left();
      // The widget is tapped: the phone hands the action over before the
      // app is in front.
      g.ask(QuickAction.expense);
      expect(g.quick.value, isNull);
      running += const Duration(minutes: 5);
      expect(g.returned(), isTrue);
      expect(g.quick.value, isNull, reason: 'the ledger is closing');
      await pumpEventQueue();
      expect(startup.state, isA<Locked>());
      expect(g.quick.value, isNull);
      await startup.unlockWithPassword(_password);
      expect(g.quick.value, QuickAction.expense, reason: 'not lost');
    });

    test('asked for while the app is behind and back in time, it opens '
        'when the app is in front', () async {
      await startup.setUp(_password);
      final g = gate();
      g.left();
      g.ask(QuickAction.income);
      running += const Duration(seconds: 5);
      expect(g.returned(), isFalse);
      expect(g.quick.value, QuickAction.income);
    });

    test('an action the screens had not acted on when the ledger locked is '
        'kept for the next opening', () async {
      await startup.setUp(_password);
      final g = gate();
      g.ask(QuickAction.expense);
      // Not taken yet (the book is still loading), and the ledger locks.
      startup.lock();
      expect(g.quick.value, isNull);
      await startup.unlockWithPassword(_password);
      expect(g.quick.value, QuickAction.expense);
    });

    test('the newest action asked for while locked is the one kept', () async {
      await startup.setUp(_password);
      startup.lock();
      final g = gate();
      g.ask(QuickAction.expense);
      g.ask(QuickAction.income);
      await startup.unlockWithPassword(_password);
      expect(g.quick.value, QuickAction.income);
    });
  });

  group('a restore given up (F92)', () {
    setUp(() => startup.setUp(_password));

    test('the ledger reopens on the page the person left from, once', () async {
      final g = gate();
      g.place = const SettingsRoute(SettingsDestination.backup);
      startup.lockToRestore();
      expect(g.place, isNull);
      await startup.cancelRestore();
      expect(g.takeReturn(), const SettingsRoute(SettingsDestination.backup));
      expect(g.takeReturn(), isNull, reason: 'once');
    });

    test('a restore that went through, or an ordinary lock, goes back '
        'nowhere', () async {
      final g = gate();
      g.place = AppRoutes.settings;
      startup.lock();
      await startup.unlockWithPassword(_password);
      expect(g.takeReturn(), isNull);
      // Left for a restore, then unlocked by the password instead.
      g.place = AppRoutes.settings;
      startup.lockToRestore();
      startup.lock();
      await startup.unlockWithPassword(_password);
      expect(g.takeReturn(), isNull);
    });

    test('away too long on the restore form, the keys held for giving it '
        'up are let go', () async {
      final g = gate();
      startup.lockToRestore();
      expect(startup.canResume, isTrue);
      g.left();
      expect(g.covered, isTrue);
      running += const Duration(minutes: 5);
      expect(g.returned(), isTrue);
      expect(startup.canResume, isFalse);
      expect(g.covered, isFalse);
    });

    test('back in time, they are kept', () {
      final g = gate();
      startup.lockToRestore();
      expect(away(g, const Duration(minutes: 1)), isFalse);
      expect(startup.canResume, isTrue);
    });
  });
}
