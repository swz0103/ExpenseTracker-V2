import 'dart:io';

import 'package:expense_tracker/src/core/navigation/nav.dart';
import 'package:expense_tracker/src/core/platform/app_lifecycle.dart';
import 'package:expense_tracker/src/core/platform/away_clock.dart';
import 'package:expense_tracker/src/core/platform/lock_gate.dart';
import 'package:expense_tracker/src/core/platform/preferences.dart';
import 'package:expense_tracker/src/core/platform/startup.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:vault/backup_security.dart';
import 'package:vault/ledger_vault.dart';

const _password = 'correct horse battery';

/// What the open ledger was told, in order.
final class _Session implements LifecycleSession {
  _Session(this.heard, this.gate);

  final List<String> heard;
  final LockGate<AppRoute> gate;

  @override
  void leave() => heard.add('leave');

  @override
  void returned() =>
      heard.add(gate.closing ? 'returned while closing' : 'returned');
}

/// The one owner of leaving and coming back (ARC-04, ARC-05), on a real
/// lock gate and encrypted ledger, with the phone's events played as the
/// phone sends them and a clock the test moves.
void main() {
  late Directory directory;
  late Startup startup;
  late AutoLock choice;
  late Duration running;
  late bool errand;
  late List<String> heard;
  late LockGate<AppRoute> gate;
  late AppLifecycle lifecycle;

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('app-lifecycle-');
    startup = Startup(
      LedgerVault(
        directory,
        codec: KeyringCodec(kdf: PasswordKdf.insecureForTests),
      ),
    );
    await startup.setUp(_password);
    choice = AutoLock.fiveMinutes;
    running = Duration.zero;
    errand = false;
    heard = [];
    gate = LockGate<AppRoute>(
      startup,
      autoLock: () => choice,
      clock: AwayClock(running: () => running),
      onErrand: () => errand,
    );
    // What the gate says, as it says it, beside what the session hears.
    gate.addListener(() {
      if (gate.closing && !heard.contains('lock')) heard.add('lock');
    });
    lifecycle = AppLifecycle(gate)..attach(_Session(heard, gate));
  });

  tearDown(() {
    if (startup.state is Ready) startup.lock();
    gate.dispose();
    directory.deleteSync(recursive: true);
  });

  void play(List<AppLifecycleState> states) =>
      states.forEach(lifecycle.changed);

  /// Android's own order of leaving and of coming back.
  const leaving = [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
  ];
  const coming = [
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ];

  test('hidden and paused of one leave are one leave: the backup runs '
      'once (ARC-05)', () {
    play(leaving);
    expect(heard, ['leave']);
    expect(lifecycle.phase, LifecyclePhase.away);
    expect(gate.covered, isTrue, reason: 'covered before the backup runs');
  });

  test('back within the limit: the gate decides first, then the session '
      'books what fell due, once', () {
    play(leaving);
    running += const Duration(minutes: 4);
    play(coming);
    expect(heard, ['leave', 'returned']);
    expect(lifecycle.phase, LifecyclePhase.present);
    expect(startup.state, isA<Ready>());
  });

  test('back after the limit: the ledger locks and nothing is booked '
      '(ARC-04)', () async {
    play(leaving);
    running += const Duration(minutes: 5);
    play(coming);
    expect(heard, ['leave', 'lock']);
    expect(lifecycle.phase, LifecyclePhase.present);
    await pumpEventQueue();
    expect(startup.state, isA<Locked>());
  });

  test('a lock that starts as the app comes back keeps the session from '
      'writing', () {
    play(leaving);
    play(const [AppLifecycleState.hidden, AppLifecycleState.inactive]);
    // Locked from elsewhere (settings) between inactive and resumed.
    gate.lock().ignore();
    lifecycle.changed(AppLifecycleState.resumed);
    expect(heard, ['leave', 'lock']);
  });

  test('a trip the app sent the person on is no leave for the backup, and '
      'back from it the session goes on', () {
    errand = true;
    play(leaving);
    expect(heard, isEmpty);
    running += const Duration(minutes: 1);
    play(coming);
    expect(heard, ['returned']);
  });

  test('the notification shade (inactive, then resumed) is neither a leave '
      'nor a return', () {
    play(const [AppLifecycleState.inactive, AppLifecycleState.resumed]);
    expect(heard, isEmpty);
    expect(lifecycle.phase, LifecyclePhase.present);
  });

  test('away, back and away again at once: two leaves, two backups asked '
      'for (the services run them one after another)', () {
    play(leaving);
    play(coming);
    play(leaving);
    expect(heard, ['leave', 'returned', 'leave']);
  });

  test('gone again before resumed: the return is dropped, the leave '
      'counts', () {
    play(leaving);
    play(const [AppLifecycleState.hidden, AppLifecycleState.inactive]);
    expect(lifecycle.phase, LifecyclePhase.returning);
    play(const [AppLifecycleState.hidden, AppLifecycleState.paused]);
    expect(heard, ['leave', 'leave']);
    expect(lifecycle.phase, LifecyclePhase.away);
  });

  test('a session detached hears nothing more; detached twice is '
      'harmless', () {
    final other = _Session(heard, gate);
    lifecycle
      ..attach(other)
      ..detach(other)
      ..detach(other);
    play(leaving);
    play(coming);
    expect(heard, isEmpty);
  });
}
