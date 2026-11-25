import 'dart:io';
import 'dart:ui';

import 'package:core/app_core.dart';
import 'package:core/foundation_values.dart';
import 'package:expense_tracker/src/core/design_system/feedback.dart';
import 'package:expense_tracker/src/core/diagnostics/error_log.dart';
import 'package:expense_tracker/src/core/diagnostics/unhandled_errors.dart';
import 'package:expense_tracker/src/core/messages/diagnostics_messages.dart';
import 'package:expense_tracker/src/core/time/app_clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A fault nothing caught is kept with its stack wherever it comes from;
/// a developer still sees it, and in a release build the person is told
/// once, not on every fault.
void main() {
  const stack =
      '#0      Overview.build (package:expense_tracker/src/overview.dart:7:3)';

  late ErrorLog log;
  late List<String> told;

  setUp(() {
    log = ErrorLog.detached();
    told = [];
  });

  UnhandledErrors errors({required bool surface, bool somewhere = true}) =>
      UnhandledErrors(
        log: log,
        surface: surface,
        tell: () {
          told.add(DiagnosticsMessages.unforeseenNote);
          return somewhere;
        },
      );

  FlutterErrorDetails details(String said) => FlutterErrorDetails(
    exception: StateError(said),
    stack: StackTrace.fromString(stack),
  );

  group('while developing', () {
    test('a screen fault is kept with its stack and still shown', () {
      final shown = <FlutterErrorDetails>[];
      final present = FlutterError.presentError;
      FlutterError.presentError = shown.add;
      addTearDown(() => FlutterError.presentError = present);
      errors(surface: true).onFlutterError(details('no account 42'));
      expect(log.entries.single.$2, '畫面錯誤：StateError: Bad state: no account #');
      expect(
        log.text.split('\n').last,
        '    #0 Overview.build (package:expense_tracker/src/overview.dart:7:3)',
      );
      expect(shown.single.exception, isStateError);
      // The developer is shown the fault; the person's note is not used.
      expect(told, isEmpty);
    });

    test('any other fault is kept and left to Flutter to print', () {
      final handled = errors(surface: true).onPlatformError(
        const FormatException('x'),
        StackTrace.fromString(stack),
      );
      // False: not swallowed here, so Flutter reports it as unhandled.
      expect(handled, isFalse);
      expect(log.entries.single.$2, '未預期的錯誤：FormatException');
      expect(told, isEmpty);
    });
  });

  group('in a release build', () {
    setUp(() {
      AppClock.use(FixedClock(UtcInstant(DateTime.utc(2026, 11, 23, 4))));
    });
    tearDown(AppClock.reset);

    test('a fault is kept, not printed, and the person is told once', () {
      final shown = <FlutterErrorDetails>[];
      final present = FlutterError.presentError;
      FlutterError.presentError = shown.add;
      addTearDown(() => FlutterError.presentError = present);
      final handler = errors(surface: false);
      handler.onFlutterError(details('a'));
      expect(shown, isEmpty);
      expect(told, ['發生未預期的錯誤，已記在「設定 › 關於 › 診斷」']);
      // Dealt with: true keeps the engine from printing it.
      expect(
        handler.onPlatformError(StateError('b'), StackTrace.empty),
        isTrue,
      );
      // A screen that fails on every frame: still one note.
      for (var i = 0; i < 100; i++) {
        handler.onFlutterError(details('a'));
      }
      expect(told.length, 1);
      // Every one of them is in the log all the same.
      expect(log.entries.first.$2, '畫面錯誤：StateError: Bad state: a ×100');
      expect(log.count, 3);
    });

    test('told again only a minute after the last note', () {
      expect(UnhandledErrors.noteGap, const Duration(minutes: 1));
      final clock = FixedClock(UtcInstant(DateTime.utc(2026, 11, 23, 4)));
      AppClock.use(clock);
      final handler = errors(surface: false);
      handler.onPlatformError(StateError('a'), StackTrace.empty);
      clock.advance(const Duration(seconds: 59));
      handler.onPlatformError(StateError('b'), StackTrace.empty);
      expect(told.length, 1);
      clock.advance(const Duration(seconds: 1));
      handler.onPlatformError(StateError('c'), StackTrace.empty);
      expect(told.length, 2);
    });

    test('with nowhere to say it yet, the next fault tries again', () {
      final nowhere = errors(surface: false, somewhere: false);
      nowhere.onPlatformError(StateError('a'), StackTrace.empty);
      nowhere.onPlatformError(StateError('b'), StackTrace.empty);
      expect(told.length, 2);
    });

    test('a note that itself fails is kept, and not tried again', () {
      var asked = 0;
      final handler = UnhandledErrors(
        log: log,
        surface: false,
        tell: () {
          asked++;
          throw StateError('no screen');
        },
      );
      handler.onPlatformError(ArgumentError('a'), StackTrace.empty);
      handler.onPlatformError(ArgumentError('b'), StackTrace.empty);
      expect(asked, 1);
      expect(log.entries.map((e) => e.$2), [
        '未預期的錯誤：ArgumentError: Invalid argument(s): b',
        '未預期的錯誤：StateError: Bad state: no screen',
        '未預期的錯誤：ArgumentError: Invalid argument(s): a',
      ]);
    });

    test('a fault of the isolate is kept from the text the runtime gives', () {
      errors(surface: false)
          .onIsolateError(['Bad state: paid 500 to 全聯', stack]);
      expect(
        log.entries.single.$2,
        '背景執行錯誤：IsolateFault: Bad state: paid # to …',
      );
      expect(
        log.text.split('\n').last,
        '    #0 Overview.build (package:expense_tracker/src/overview.dart:7:3)',
      );
      expect(told.length, 1);
      // Something else than the pair the runtime sends is kept as it is.
      errors(surface: false).onIsolateError('gone');
      expect(log.entries.first.$2, '背景執行錯誤：IsolateFault: gone');
    });

    testWidgets('a fault while a screen is built is said after the frame, '
        'as a note at the bottom of whatever is open', (tester) async {
      final handler = UnhandledErrors(
        log: log,
        surface: false,
        tell: () => showNoteAnywhere(DiagnosticsMessages.unforeseenNote),
      );
      var fail = false;
      late StateSetter redraw;
      await tester.pumpWidget(
        MaterialApp(
          scaffoldMessengerKey: appMessenger,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                redraw = setState;
                if (fail) {
                  // Told from inside a build: a note cannot go up yet.
                  handler.onFlutterError(details('in build'));
                }
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      expect(find.byType(SnackBar), findsNothing);
      redraw(() => fail = true);
      await tester.pump();
      fail = false;
      await tester.pump();
      expect(find.text('發生未預期的錯誤，已記在「設定 › 關於 › 診斷」'), findsOneWidget);
      expect(tester.takeException(), isNull);
      // The note goes by itself.
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
    });
  });

  testWidgets('before the app has a screen there is nowhere to say a note', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox());
    expect(showNoteAnywhere('x'), isFalse);
  });

  group('installed', () {
    testWidgets('takes screen faults, other faults and isolate faults, and '
        'writes the log when the app is left', (tester) async {
      final directory = Directory.systemTemp.createTempSync('unhandled-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final file = File('${directory.path}/diagnostics.log');
      log.keepIn(file);
      final handler = errors(surface: false);
      final screen = FlutterError.onError;
      final other = PlatformDispatcher.instance.onError;
      handler.install();
      final installedScreen = FlutterError.onError;
      final installedOther = PlatformDispatcher.instance.onError;
      // Put back at once: the test framework watches both itself.
      FlutterError.onError = screen;
      PlatformDispatcher.instance.onError = other;
      addTearDown(handler.dispose);

      installedScreen!(details('a'));
      expect(installedOther!(StateError('b'), StackTrace.empty), isTrue);
      expect(log.entries.map((e) => e.$2), [
        '未預期的錯誤：StateError: Bad state: b',
        '畫面錯誤：StateError: Bad state: a',
      ]);

      // Each fault asked for a write; with those done, one recorded later
      // waits its two seconds, unless the app is left first.
      Future<void> written(int lines) async {
        for (var i = 0; i < 400; i++) {
          if (file.existsSync() && file.readAsLinesSync().length == lines) {
            return;
          }
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)),
          );
          await tester.pump();
        }
        fail(file.existsSync() ? file.readAsStringSync() : 'no file');
      }

      await written(2);
      log.record('later', StateError('c'), StackTrace.empty);
      expect(file.readAsLinesSync().length, 2);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await written(3);
      expect(
        file.readAsLinesSync().last,
        contains('"what":"later：StateError: Bad state: c"'),
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });
  });
}
