/// D84: a step running by itself that fails is told, once a run; review
/// 31: a note counts as told only once it was on screen to be read, and
/// two at once wait their turn instead of hiding each other.
library;

import 'dart:async';

import 'package:expense_tracker/src/app/quiet_failures.dart';
import 'package:expense_tracker/src/core/design_system/design_system.dart';
import 'package:expense_tracker/src/core/messages/problem_messages.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('each kind is said once a run, in a sentence with where the '
      'details are', () async {
    final said = <String>[];
    final quiet = QuietFailures((note) async {
      said.add(note);
      return true;
    });
    quiet
      ..failed(QuietStep.backgroundBackup)
      ..failed(QuietStep.backgroundBackup)
      ..failed(QuietStep.calendarSync);
    await pumpEventQueue();
    quiet.failed(QuietStep.backgroundBackup);
    await pumpEventQueue();
    expect(said, ['背景備份沒有完成，可在診斷匯出詳細資料', '提醒沒有同步到日曆，可在診斷匯出詳細資料']);
  });

  test('a note not read (another took its place, or it could not be '
      'shown) is said again at the next failure', () async {
    final said = <String>[];
    var read = false;
    final quiet = QuietFailures((note) async {
      said.add(note);
      if (said.length == 2) throw StateError('no messenger');
      return read;
    });
    quiet.failed(QuietStep.marketRefresh);
    await pumpEventQueue();
    quiet.failed(QuietStep.marketRefresh);
    await pumpEventQueue();
    read = true;
    quiet.failed(QuietStep.marketRefresh);
    await pumpEventQueue();
    quiet.failed(QuietStep.marketRefresh);
    await pumpEventQueue();
    // Not read, failed to show, read; then told.
    expect(said, hasLength(3));
  });

  test('while its note waits, the step is not said twice; notes dropped '
      'unseen are said again', () async {
    final waiting = <Completer<bool>>[];
    final quiet = QuietFailures((note) {
      final shown = Completer<bool>();
      waiting.add(shown);
      return shown.future;
    });
    quiet
      ..failed(QuietStep.autoBooking)
      ..failed(QuietStep.autoBooking);
    expect(waiting, hasLength(1));
    // The opening ended and the messenger cleared its queue.
    quiet.dropWaiting();
    quiet.failed(QuietStep.autoBooking);
    expect(waiting, hasLength(2));
    // The first, dropped, never says; the second is read.
    waiting[1].complete(true);
    await pumpEventQueue();
    quiet.failed(QuietStep.autoBooking);
    expect(waiting, hasLength(2));
    waiting[0].complete(false);
  });

  test('another book in place (a restore, a key reset) is told again of '
      'what is about the book; what is about the run stays told; a note '
      'read about the book before tells nothing of the new one '
      '(review 33)', () async {
    final said = <QuietStep>[];
    final shown = <Completer<bool>>[];
    var book = 1;
    final quiet = QuietFailures((note) {
      said.add(QuietStep.values.firstWhere((s) => s.note == note));
      final read = Completer<bool>();
      shown.add(read);
      return read.future;
    }, book: () => book);
    for (final step in QuietStep.values) {
      quiet.failed(step);
    }
    for (final read in shown) {
      read.complete(true);
    }
    await pumpEventQueue();
    expect(said, QuietStep.values);
    // Without another book (a lock and an unlock), nothing again.
    for (final step in QuietStep.values) {
      quiet.failed(step);
    }
    expect(said, hasLength(QuietStep.values.length));

    said.clear();
    book++;
    for (final step in QuietStep.values) {
      quiet.failed(step);
    }
    expect(said, [
      QuietStep.autoBooking,
      QuietStep.integrityCheck,
      QuietStep.leftoverPhoto,
      QuietStep.receiptSweep,
    ]);
    // These four are on screen when yet another book takes their place:
    // read, they still say nothing of it.
    book++;
    for (final read in shown.skip(QuietStep.values.length)) {
      read.complete(true);
    }
    await pumpEventQueue();
    said.clear();
    quiet
      ..failed(QuietStep.integrityCheck)
      ..failed(QuietStep.marketRefresh);
    expect(said, [QuietStep.integrityCheck]);
    shown.last.complete(true);
    await pumpEventQueue();
    quiet.failed(QuietStep.integrityCheck);
    expect(said, [QuietStep.integrityCheck]);
  });

  test('the steps about the book are those of one book; the rest are of '
      'the run', () {
    expect(
      {for (final s in QuietStep.values.where((s) => s.perBook)) s},
      {
        QuietStep.autoBooking,
        QuietStep.integrityCheck,
        QuietStep.leftoverPhoto,
        QuietStep.receiptSweep,
      },
    );
  });

  test('every quiet step has its words', () {
    expect(
      {for (final s in QuietStep.values) s.note},
      {
        '到期的定期交易沒有自動入帳，可在診斷匯出詳細資料',
        '背景備份沒有完成，可在診斷匯出詳細資料',
        '收盤價與匯率沒有更新，可在診斷匯出詳細資料',
        '提醒沒有同步到日曆，可在診斷匯出詳細資料',
        '帳本健檢沒有通過，可在診斷匯出詳細資料',
        '相機拍的收據照片沒有找回，可在診斷匯出詳細資料',
        '不再使用的收據照片沒有清除，可在診斷匯出詳細資料',
      },
    );
  });

  group('on screen (queueNote)', () {
    Future<void> app(WidgetTester tester) => tester.pumpWidget(
      MaterialApp(
        scaffoldMessengerKey: appMessenger,
        home: const Scaffold(body: SizedBox()),
      ),
    );

    testWidgets('two failures at once: each note is read in turn, and '
        'each step told once', (tester) async {
      await app(tester);
      final quiet = QuietFailures(queueNote);
      quiet
        ..failed(QuietStep.autoBooking)
        ..failed(QuietStep.marketRefresh);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text(QuietStep.autoBooking.note), findsOneWidget);
      expect(find.text(QuietStep.marketRefresh.note), findsNothing);
      // The first goes by itself after 3 s; the second follows.
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.text(QuietStep.autoBooking.note), findsNothing);
      expect(find.text(QuietStep.marketRefresh.note), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      // Both read: told once, never again this run.
      quiet
        ..failed(QuietStep.autoBooking)
        ..failed(QuietStep.marketRefresh);
      await tester.pump();
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('a quiet note another note takes the place of is told '
        'again at its next failure', (tester) async {
      await app(tester);
      final quiet = QuietFailures(queueNote);
      quiet.failed(QuietStep.calendarSync);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text(QuietStep.calendarSync.note), findsOneWidget);
      // An ordinary note, as after a save, takes its place.
      showNoteAnywhere('已儲存');
      await tester.pumpAndSettle();
      expect(find.text(QuietStep.calendarSync.note), findsNothing);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      quiet.failed(QuietStep.calendarSync);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text(QuietStep.calendarSync.note), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    });

    test('with nowhere to say it, a note is not read', () async {
      expect(appMessenger.currentState, isNull);
      expect(await queueNote('x'), isFalse);
    });
  });
}
