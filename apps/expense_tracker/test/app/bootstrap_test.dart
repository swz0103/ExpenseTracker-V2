import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:expense_tracker/src/app/bootstrap.dart';
import 'package:expense_tracker/src/app/load_failed_page.dart';
import 'package:expense_tracker/src/app/settings_page.dart';
import 'package:core/app_core.dart';
import 'package:core/foundation_values.dart';
import 'package:expense_tracker/src/app/shell.dart';
import 'package:expense_tracker/src/core/diagnostics/error_log.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/ledger/persistence/codec/record_json.dart';
import 'package:expense_tracker/src/core/time/app_clock.dart';
import 'package:expense_tracker/src/core/design_system/feedback.dart';
import 'package:expense_tracker/src/core/design_system/keys.dart';
import 'package:expense_tracker/src/core/navigation/nav.dart';
import 'package:expense_tracker/src/core/platform/away_clock.dart';
import 'package:expense_tracker/src/core/platform/preferences.dart';
import 'package:expense_tracker/src/core/platform/preference_choices.dart';
import 'package:expense_tracker/src/core/platform/quick_action.dart';
import 'package:expense_tracker/src/core/platform/screen_privacy.dart';
import 'package:expense_tracker/src/core/platform/startup.dart';
import 'package:expense_tracker/src/features/lock/ui/lock_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vault/backup_security.dart';
import 'package:vault/ledger_vault.dart';

import '../support/places.dart' show go;

const _password = 'correct horse battery';

/// The whole app behind its one lock gate, on a real encrypted ledger
/// (work package 3.1): what is on screen when the ledger locks, the path
/// a shortcut, the widget or a notification takes, the cover while away,
/// screenshots, and a restore given up.
void main() {
  late Directory directory;
  late Startup startup;
  late Preferences preferences;

  /// Time that only runs forward, as the away clock reads it.
  late Duration running;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('gate-');
    startup = Startup(
      LedgerVault(
        directory,
        codec: KeyringCodec(kdf: PasswordKdf.insecureForTests),
      ),
    );
    preferences = Preferences();
    running = Duration.zero;
  });

  tearDown(() {
    if (startup.state is Ready) startup.lock();
    directory.deleteSync(recursive: true);
  });

  /// Lets real work (files, key derivation, the book loading) finish.
  Future<void> until(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 80 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    await tester.pump(const Duration(seconds: 1));
  }

  bool shown(Finder finder) => finder.evaluate().isNotEmpty;

  Future<void> untilBook(WidgetTester tester) =>
      until(tester, () => shown(find.byType(AppShell)));

  Future<void> root(
    WidgetTester tester, {
    ValueNotifier<QuickAction?>? quick,
    ScreenPrivacy? privacy,
    Future<void> Function()? leave,
  }) async {
    tester.view.physicalSize = const Size(400, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      VaultRoot(
        startup: startup,
        preferences: preferences,
        quick: quick,
        privacy: privacy,
        leave: leave,
        awayClock: AwayClock(running: () => running),
      ),
    );
    await tester.pump();
  }

  /// A ledger with a password, open; its recovery code already seen, so
  /// no dialog of it is in the way.
  Future<void> setUpLedger(WidgetTester tester) async {
    await tester.runAsync(() => startup.setUp(_password));
    startup.takeRecoveryCode();
  }

  Future<void> unlock(WidgetTester tester) async {
    await tester.runAsync(() => startup.unlockWithPassword(_password));
    await untilBook(tester);
  }

  void lifecycle(WidgetTester tester, AppLifecycleState state) =>
      tester.binding.handleAppLifecycleStateChanged(state);

  /// Leaves the app as the phone does, stays away [time], and comes back.
  Future<void> awayFor(WidgetTester tester, Duration time) async {
    lifecycle(tester, AppLifecycleState.inactive);
    lifecycle(tester, AppLifecycleState.hidden);
    lifecycle(tester, AppLifecycleState.paused);
    await tester.pump();
    running += time;
    lifecycle(tester, AppLifecycleState.hidden);
    lifecycle(tester, AppLifecycleState.inactive);
    lifecycle(tester, AppLifecycleState.resumed);
    await tester.pump();
  }

  const sheetWords = '帳務內容：台新銀行 385,400';
  const pageWords = '全螢幕頁：郵局儲蓄 320,000';
  const dialogWords = '對話框：停車場 40';
  const noteWords = '提示：已記下 7-ELEVEN 45';

  testWidgets('locking leaves nothing of the ledger on screen or in the '
      'tree: a sheet, a pushed page, a dialog and a note all go (SEC-05)', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await setUpLedger(tester);
    await root(tester);
    await untilBook(tester);
    final context = tester.element(find.byType(AppShell));
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text(pageWords)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final over = tester.element(find.text(pageWords));
    unawaited(showSheet<void>(over, (_) => const Text(sheetWords)));
    await tester.pumpAndSettle();
    unawaited(
      showDialog<void>(
        context: tester.element(find.text(sheetWords)),
        builder: (_) => const AlertDialog(content: Text(dialogWords)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(pageWords, skipOffstage: false), findsOneWidget);
    expect(find.text(sheetWords), findsOneWidget);
    expect(find.text(dialogWords), findsOneWidget);
    expect(showNoteAnywhere(noteWords), isTrue);
    await tester.pump();
    expect(find.text(noteWords), findsOneWidget);

    startup.lock();
    await tester.pump();
    for (final words in [pageWords, sheetWords, dialogWords, noteWords]) {
      expect(find.text(words, skipOffstage: false), findsNothing);
      expect(find.semantics.byLabel(words), findsNothing);
    }
    expect(find.byType(AppShell, skipOffstage: false), findsNothing);
    expect(find.byType(LockScreen), findsOneWidget);
    // And still nothing once every animation has run out.
    await tester.pumpAndSettle();
    expect(find.text(sheetWords, skipOffstage: false), findsNothing);
    expect(find.text(noteWords, skipOffstage: false), findsNothing);
    expect(find.byType(AppShell, skipOffstage: false), findsNothing);
    semantics.dispose();
  });

  testWidgets('the lock screen can still open sheets of its own, and '
      'unlocking takes them away', (tester) async {
    await setUpLedger(tester);
    startup.lock();
    await root(tester);
    final context = tester.element(find.byType(LockScreen));
    unawaited(showSheet<void>(context, (_) => const Text(sheetWords)));
    await tester.pumpAndSettle();
    expect(find.text(sheetWords), findsOneWidget);
    await unlock(tester);
    expect(find.text(sheetWords, skipOffstage: false), findsNothing);
    expect(find.byType(AppShell), findsOneWidget);
  });

  group('ways in (F43)', () {
    testWidgets('a widget or notification tap on a locked ledger shows the '
        'lock screen only; after unlocking, the form asked for opens', (
      tester,
    ) async {
      await setUpLedger(tester);
      startup.lock();
      final quick = ValueNotifier<QuickAction?>(QuickAction.expense);
      addTearDown(quick.dispose);
      await root(tester, quick: quick);
      await tester.pump(const Duration(seconds: 1));
      expect(quick.value, isNull, reason: 'the gate took it');
      expect(find.byType(LockScreen), findsOneWidget);
      expect(find.byKey(Keys.save), findsNothing, reason: 'no composer');
      expect(find.byType(AppShell), findsNothing, reason: 'no balances');

      await unlock(tester);
      await tester.pumpAndSettle();
      expect(find.byKey(Keys.save), findsOneWidget, reason: 'not lost');
    });

    testWidgets('a tap that arrives as the app comes back too late opens '
        'nothing over the lock, and the form opens after unlocking', (
      tester,
    ) async {
      await setUpLedger(tester);
      final quick = ValueNotifier<QuickAction?>(null);
      addTearDown(quick.dispose);
      await root(tester, quick: quick);
      await untilBook(tester);

      lifecycle(tester, AppLifecycleState.inactive);
      lifecycle(tester, AppLifecycleState.hidden);
      lifecycle(tester, AppLifecycleState.paused);
      await tester.pump();
      running += const Duration(minutes: 5);
      // The phone hands the action over before the app is in front.
      quick.value = QuickAction.income;
      await tester.pump();
      expect(find.byKey(Keys.save), findsNothing);
      lifecycle(tester, AppLifecycleState.hidden);
      lifecycle(tester, AppLifecycleState.inactive);
      lifecycle(tester, AppLifecycleState.resumed);
      await tester.pump();
      expect(find.byKey(Keys.save), findsNothing);
      await until(tester, () => startup.state is Locked);
      expect(find.byType(LockScreen), findsOneWidget);
      expect(find.byKey(Keys.save), findsNothing);
      expect(find.byType(AppShell, skipOffstage: false), findsNothing);

      await unlock(tester);
      await tester.pumpAndSettle();
      expect(find.byKey(Keys.save), findsOneWidget);
    });

    testWidgets('with the ledger open and in front the form opens at once', (
      tester,
    ) async {
      await setUpLedger(tester);
      final quick = ValueNotifier<QuickAction?>(null);
      addTearDown(quick.dispose);
      await root(tester, quick: quick);
      await untilBook(tester);
      quick.value = QuickAction.expense;
      await tester.pumpAndSettle();
      expect(find.byKey(Keys.save), findsOneWidget);
    });
  });

  group('a screen left open over midnight (review 16)', () {
    // 2026-10-31 23:59 UTC (this clock stands in UTC): two minutes on is
    // 11-01, another month.
    late FixedClock clock;
    setUp(() {
      clock = FixedClock(UtcInstant(DateTime.utc(2026, 10, 31, 23, 59)));
      AppClock.use(clock);
    });
    tearDown(AppClock.reset);

    testWidgets('moves on to the new day by itself: the month it shows is '
        'then named, no longer 本月', (tester) async {
      await setUpLedger(tester);
      await root(tester);
      await untilBook(tester);
      final ledger = tester.widget<AppShell>(find.byType(AppShell)).ledger;
      expect(ledger.today, DateTime.utc(2026, 10, 31));
      expect(find.text('本月結餘'), findsOneWidget);
      clock.advance(const Duration(minutes: 2));
      await tester.pump(const Duration(minutes: 2));
      await tester.pump();
      expect(ledger.today, DateTime.utc(2026, 11, 1));
      expect(find.text('10 月結餘'), findsOneWidget);
      expect(find.text('本月結餘'), findsNothing);
    });
  });

  group('coming back with an item due (ARC-04)', () {
    // 2026-11-04 23:58 UTC (this clock stands in UTC); three minutes away
    // makes it 11-05 00:01, the day the item falls due.
    late FixedClock clock;
    setUp(() {
      clock = FixedClock(UtcInstant(DateTime.utc(2026, 11, 4, 23, 58)));
      AppClock.use(clock);
    });
    tearDown(AppClock.reset);

    /// The open book, given an item that books itself on the 5th from
    /// 2026-11-05.
    Ledger bookWithRent(WidgetTester tester) {
      final ledger = tester.widget<AppShell>(find.byType(AppShell)).ledger;
      ledger.recurringCommands.saveRecurring(
        Recurring(
          id: 'rent',
          name: '房租',
          amount: 500,
          day: 5,
          account: ledger.accounts.all.first.id,
          category: '居家生活',
          auto: true,
          start: DateTime.utc(2026, 11, 5),
        ),
      );
      return ledger;
    }

    int booked(Ledger ledger) =>
        ledger.entries.all.where((e) => e.recurring == 'rent').length;

    testWidgets('back within the time, what fell due meanwhile is booked '
        'once', (tester) async {
      await setUpLedger(tester);
      await root(tester);
      await untilBook(tester);
      final ledger = bookWithRent(tester);
      expect(booked(ledger), 0);
      clock.advance(const Duration(minutes: 3));
      await awayFor(tester, const Duration(minutes: 3));
      await until(tester, () => booked(ledger) > 0);
      expect(startup.state, isA<Ready>());
      expect(booked(ledger), 1);
    });

    testWidgets('a lock that is done before the app is resumed never lets '
        'it be written to the closed ledger', (tester) async {
      await setUpLedger(tester);
      await root(tester);
      await untilBook(tester);
      bookWithRent(tester);
      await tester.runAsync(() => pumpEventQueue());
      final before = ErrorLog.instance.entries.length;
      lifecycle(tester, AppLifecycleState.inactive);
      lifecycle(tester, AppLifecycleState.hidden);
      lifecycle(tester, AppLifecycleState.paused);
      await tester.pump();
      running += const Duration(minutes: 5);
      clock.advance(const Duration(minutes: 5));
      lifecycle(tester, AppLifecycleState.hidden);
      lifecycle(tester, AppLifecycleState.inactive);
      // The lock finishes between inactive and resumed, before a frame:
      // the ledger's screens are still in the tree, its store closed.
      for (var i = 0; i < 80 && startup.state is! Locked; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
      }
      expect(startup.state, isA<Locked>());
      lifecycle(tester, AppLifecycleState.resumed);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump();
      // Before the fix: 寫入帳本: DataSourceException(Bad state: Store is
      // closed.), the booking kept only in memory.
      expect(
        ErrorLog.instance.entries.take(
          ErrorLog.instance.entries.length - before,
        ),
        isEmpty,
      );
      expect(find.byType(LockScreen), findsOneWidget);

      // Unlocked again, the item is booked once, on the open ledger.
      await unlock(tester);
      final ledger = tester.widget<AppShell>(find.byType(AppShell)).ledger;
      expect(booked(ledger), 1);
    });
  });

  group('away (SEC-07)', () {
    testWidgets('off the screen the ledger is covered at once; back within '
        'the time it shows again as it was', (tester) async {
      await setUpLedger(tester);
      await root(tester);
      await untilBook(tester);
      await tester.tap(find.byKey(Keys.tab('帳戶')));
      await tester.pumpAndSettle();
      final shell = tester.state(find.byType(AppShell));

      lifecycle(tester, AppLifecycleState.inactive);
      await tester.pump();
      expect(
        find.byKey(Keys.lockCover),
        findsNothing,
        reason: 'still in front',
      );
      lifecycle(tester, AppLifecycleState.hidden);
      await tester.pump();
      expect(find.byKey(Keys.lockCover), findsOneWidget);
      lifecycle(tester, AppLifecycleState.paused);
      running += const Duration(minutes: 4, seconds: 59);
      lifecycle(tester, AppLifecycleState.hidden);
      lifecycle(tester, AppLifecycleState.inactive);
      await tester.pump();
      expect(find.byKey(Keys.lockCover), findsNothing);
      lifecycle(tester, AppLifecycleState.resumed);
      await tester.pump();
      expect(startup.state, isA<Ready>());
      expect(tester.state(find.byType(AppShell)), same(shell));
    });

    testWidgets('back after the time, the ledger is never drawn again: the '
        'cover stays until the lock screen takes its place', (tester) async {
      await setUpLedger(tester);
      await root(tester);
      await untilBook(tester);
      lifecycle(tester, AppLifecycleState.inactive);
      lifecycle(tester, AppLifecycleState.hidden);
      lifecycle(tester, AppLifecycleState.paused);
      await tester.pump();
      running += const Duration(minutes: 5);
      lifecycle(tester, AppLifecycleState.hidden);
      lifecycle(tester, AppLifecycleState.inactive);
      // Decided as the app comes back, before a frame is drawn.
      await tester.pump();
      expect(
        shown(find.byKey(Keys.lockCover)) || shown(find.byType(LockScreen)),
        isTrue,
      );
      lifecycle(tester, AppLifecycleState.resumed);
      await until(tester, () => startup.state is Locked);
      expect(find.byType(LockScreen), findsOneWidget);
      expect(find.byKey(Keys.lockCover), findsNothing);
      expect(find.byType(AppShell, skipOffstage: false), findsNothing);
    });

    testWidgets('the time is the person\'s choice: with 立即 any trip away '
        'locks, with 不自動上鎖 none does', (tester) async {
      await setUpLedger(tester);
      await root(tester);
      await untilBook(tester);
      preferences.update(autoLock: AutoLock.never);
      await awayFor(tester, const Duration(days: 2));
      expect(startup.state, isA<Ready>());
      expect(find.byType(AppShell), findsOneWidget);

      preferences.update(autoLock: AutoLock.immediately);
      await awayFor(tester, Duration.zero);
      await until(tester, () => startup.state is Locked);
      expect(startup.state, isA<Locked>());
      expect(find.byType(LockScreen), findsOneWidget);
    });
  });

  testWidgets('screenshots are kept off whatever shows while no ledger is '
      'open, and allowed over the open ledger unless 禁止截圖 is on (SEC-08)', (
    tester,
  ) async {
    final told = <bool>[];
    final privacy = ScreenPrivacy(directory, (on) async => told.add(on));
    await root(tester, privacy: privacy);
    expect(told, [true], reason: 'the welcome');
    await setUpLedger(tester);
    await untilBook(tester);
    expect(told, [true, false]);
    startup.lock();
    await tester.pump();
    expect(told, [true, false, true]);
    await tester.runAsync(() => privacy.turn(on: true));
    await unlock(tester);
    expect(told, [true, false, true, true, true]);
  });

  testWidgets('a restore from settings given up reopens the ledger on the '
      'page it was started from, with no unlocking (F92)', (tester) async {
    await setUpLedger(tester);
    await root(tester);
    await untilBook(tester);
    await go(tester, ['更多', '設定', '安全']);
    final page = find.byWidgetPredicate(
      (w) => w is SettingsPage && w.part == SettingsDestination.security,
    );
    expect(page, findsOneWidget);

    startup.lockToRestore();
    await tester.pump();
    expect(find.byType(LockScreen), findsOneWidget);
    expect(find.byKey(Keys.restoreGo), findsOneWidget);
    await tester.tap(find.byKey(Keys.back));
    await untilBook(tester);
    await tester.pumpAndSettle();
    expect(startup.state, isA<Ready>());
    expect(find.byType(LockScreen), findsNothing);
    expect(page, findsOneWidget);
  });

  testWidgets('a book that fails its check is told once a book: not again '
      'at an unlock, again once new keys put another book in place '
      '(review 33)', (tester) async {
    const note = '帳本健檢沒有通過，可在診斷匯出詳細資料';
    await setUpLedger(tester);
    // An entry paid from an account the book does not have.
    (startup.state as Ready).vault.store.write(
      (w) => w.put(
        'entry',
        'orphan',
        jsonEncode(
          entryToJson(
            Entry(
              id: 'orphan',
              date: DateTime.utc(2026, 1, 1),
              type: EntryType.expense,
              amount: 100,
              account: 'gone',
            ),
          ),
        ),
      ),
    );
    await root(tester);
    await untilBook(tester);
    expect(find.text(note), findsOneWidget);
    // Read to the end.
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.text(note), findsNothing);

    // The book's own work at opening (its backup) done first.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    startup.lock();
    await tester.pump();
    await unlock(tester);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(seconds: 2));
      expect(find.text(note), findsNothing);
    }

    await tester.runAsync(() => startup.resetKeys(password: _password));
    startup
      ..takeRecoveryCode()
      ..takeKeysReset();
    await tester.pump();
    await untilBook(tester);
    // Its turn may come behind another note (the backup the lock cut).
    for (var i = 0; i < 6 && !shown(find.text(note)); i++) {
      await tester.pump(const Duration(seconds: 2));
    }
    expect(find.text(note), findsOneWidget);
  });

  testWidgets('back on the first screen puts the app behind, and the '
      'ledger stays open (F67)', (tester) async {
    var left = 0;
    await setUpLedger(tester);
    await root(tester, leave: () async => left++);
    await untilBook(tester);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(left, 1);
    expect(startup.state, isA<Ready>());
    expect(find.byType(AppShell), findsOneWidget);
  });

  group('a damaged ledger file (D94)', () {
    testWidgets('found as it opens: the damaged page, then the backup form', (
      tester,
    ) async {
      await setUpLedger(tester);
      // As the book's first opening writes its first records (D102).
      (startup.state as Ready).vault.store.write(
        (w) => w.put('account', 'a', '{}'),
      );
      startup.lock();
      final vault = File('${directory.path}/ledger.db');
      vault.writeAsBytesSync(const []);
      await root(tester);
      await tester.runAsync(() async {
        try {
          await startup.unlockWithPassword(_password);
        } on Object {
          // Shown on the page below.
        }
      });
      await tester.pump();
      expect(find.byType(DamagedBookPage), findsOneWidget);
      expect(vault.existsSync(), isFalse, reason: 'set aside');
      await tester.tap(find.byKey(Keys.loadFailed('restore')));
      await tester.pump();
      expect(find.byType(LockScreen), findsOneWidget);
      expect(find.byKey(Keys.restoreGo), findsOneWidget);
    });

    testWidgets('found as the book is read where its records still read '
        'whole: made again from them, and opened (D102)', (tester) async {
      await setUpLedger(tester);
      final open = (startup.state as Ready).vault;
      open.store.write((w) {
        for (var i = 0; i < 3000; i++) {
          w.put('gone', 'entry/e$i', '{"at":${i + 1}}');
        }
      });
      startup.lock();
      final file = File('${directory.path}/ledger.db');
      final bytes = file.readAsBytesSync();
      // Page 20 of the file, all zeros: not one the records are read
      // from (the first page still opens; the rows read whole).
      bytes.fillRange(4096 * 20, 4096 * 21, 0);
      file.writeAsBytesSync(bytes);
      await root(tester);
      await tester.runAsync(() => startup.unlockWithPassword(_password));
      await untilBook(tester);
      expect(find.byType(DamagedBookPage), findsNothing);
      final again = (startup.state as Ready).vault;
      expect(again.store.isOpen, isTrue);
      // The old file set aside once, to send for a look (review 18).
      expect(
        directory.listSync().where(
          (f) => f.path.endsWith('.db') && f.path.contains('ledger-damaged'),
        ),
        hasLength(1),
      );
      expect(file.existsSync(), isTrue);
    });
  });
}
