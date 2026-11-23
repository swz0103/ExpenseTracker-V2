import 'dart:io';

import 'package:core/app_core.dart';
import 'package:core/foundation_values.dart';
import 'package:expense_tracker/src/core/diagnostics/error_log.dart';
import 'package:expense_tracker/src/core/time/app_clock.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// What the error log keeps of an error can be exported: it must never carry
/// what the person wrote, amounts, or where their files are. It keeps where
/// in the code the fault was, costs the caller no file work, and stays
/// bounded.
void main() {
  test('paths, quoted words, numbers and Chinese are taken out', () {
    final cases = <Object, String>{
      const FileSystemException(
        'Cannot open file',
        '/data/user/0/io.github.swz0103.expensetracker/files/ledger.db',
        OSError('No such file', 2),
      ): 'FileSystemException: Cannot open file (errno 2)',
      StateError("Entry '午餐 120' missing"):
          'StateError: Bad state: Entry … missing',
      const FormatException('amount 12345 for 全聯'):
          'FormatException: FormatException: amount # for …',
      PlatformException(code: 'key-invalidated', message: '/secret/path'):
          'PlatformException: key-invalidated',
      ArgumentError('see C:\\Users\\me\\記帳本.etbk'):
          'ArgumentError: Invalid argument(s): see …',
    };
    for (final MapEntry(key: error, value: kept) in cases.entries) {
      final said = ErrorLog.describe(error);
      expect(said, kept, reason: '$error');
      expect(said, isNot(contains('/data/')));
      // Nothing the person wrote: no Chinese, only ASCII and the ellipsis.
      expect(RegExp(r'[^\x20-\x7e…]').hasMatch(said), isFalse, reason: said);
    }
  });

  test('a long message is cut to one short line', () {
    final said = ErrorLog.describe(StateError('x' * 500 + '\nsecond line'));
    expect(said, isNot(contains('second')));
    expect(ErrorLog.longestMessage, 120);
    // 'StateError: ' (12) + 120 kept + '…' (1).
    expect(said.length, 133);
  });

  test('an amount and a note in an error never reach the file', () async {
    final directory = Directory.systemTemp.createTempSync('error-log-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = File('${directory.path}/diagnostics.log');
    AppClock.use(FixedClock(UtcInstant(DateTime.utc(2026, 11, 23, 4))));
    addTearDown(AppClock.reset);
    final log = ErrorLog.detached()..keepIn(file);
    log.record(
      '記一筆',
      StateError("Cannot save 98765 for '王小明的生日禮物' in 全聯 /sdcard/DCIM/a.jpg"),
      StackTrace.fromString(
        '#0      Ledger.save (package:expense_tracker/src/ledger.dart:12:5)\n'
        '#1      note 98765 王小明 (file:///home/me/秘密/x.dart:3:1)\n',
      ),
    );
    await log.flush();
    // The redaction rule (`ErrorLog.describe`): quoted words, paths,
    // anything not ASCII and every number are taken out; of the stack
    // only a line that is a function name and a source is kept, so the
    // second one, which is neither, is dropped whole.
    final kept = file.readAsStringSync();
    expect(
      kept.substring(kept.indexOf('\t')),
      '\t記一筆：StateError: Bad state: Cannot save # for … in … …'
      '\t#0 Ledger.save (package:expense_tracker/src/ledger.dart:12:5)\n',
    );
    expect(log.text, isNot(contains('98765')));
    expect(log.text, isNot(contains('王小明')));
    expect(log.text, isNot(contains('sdcard')));
  });

  group('the stack', () {
    test("keeps function names and sources, and only a file's name", () {
      final kept = ErrorLog.frames(
        StackTrace.fromString(
          '#0      Ledger.save.<anonymous closure> '
          '(package:expense_tracker/src/ledger.dart:12:5)\n'
          '<asynchronous suspension>\n'
          '#1      new Entry (dart:core/entry.dart:7)\n'
          '#2      main (file:///home/me/Documents/app/test/a_test.dart:9:3)\n'
          '#3      ErrorLog.record '
          '(package:expense_tracker/src/core/diagnostics/error_log.dart:1:1)\n',
        ),
      );
      expect(kept, [
        '#0 Ledger.save.<anonymous closure> '
            '(package:expense_tracker/src/ledger.dart:12:5)',
        '#1 new Entry (dart:core/entry.dart:7)',
        // Not the folders it is in on somebody's disk; and the log's own
        // frame, which says nothing of the fault, is left out.
        '#2 main (a_test.dart:9:3)',
      ]);
    });

    test("a release build's addresses are kept for symbolizing", () {
      final kept = ErrorLog.frames(
        StackTrace.fromString(
          'Warning: This VM has been configured to produce stack traces\n'
          '*** *** *** *** *** *** *** *** *** *** *** *** *** *** *** ***\n'
          'pid: 4242, tid: 4250, name 1.ui\n'
          "build_id: 'a1b2c3'\n"
          'isolate_dso_base: 7b1c000000, vm_dso_base: 7b1c000000\n'
          '    #00 abs 0000007b1c1a2b3c virt 00000000001a2b3c '
          '_kDartIsolateSnapshotInstructions+0x1f2c\n',
        ),
      );
      expect(kept, [
        '#00 abs 0000007b1c1a2b3c virt 00000000001a2b3c '
            '_kDartIsolateSnapshotInstructions+0x1f2c',
      ]);
    });

    test('is bounded: eight frames, a thousand characters', () {
      String frame(int i, String name) =>
          '#$i      $name (package:expense_tracker/a.dart:$i:1)';
      final many = ErrorLog.frames(
        StackTrace.fromString(
          [for (var i = 0; i < 30; i++) frame(i, 'f')].join('\n'),
        ),
      );
      expect(ErrorLog.maxFrames, 8);
      expect(many.length, 8);
      expect(many.last, '#7 f (package:expense_tracker/a.dart:7:1)');
      // Each frame is 300 + 40 characters: three are 1,020, over the
      // 1,000 allowed, so two are kept.
      final long = ErrorLog.frames(
        StackTrace.fromString(
          [for (var i = 0; i < 5; i++) frame(i, 'g' * 300)].join('\n'),
        ),
      );
      expect(ErrorLog.maxStackChars, 1000);
      expect(long.length, 2);
    });

    test('an error caught without its stack is placed where it was kept', () {
      final log = ErrorLog.detached();
      try {
        throw const FormatException('x');
      } on FormatException catch (error) {
        log.record('step', error);
      }
      // The first frame is this test, not the log.
      expect(log.text.split('\n')[1], contains('error_log_test.dart'));
      // An Error has its own stack, from where it was thrown.
      Never thrower() => throw StateError('y');
      try {
        thrower();
      } on StateError catch (error) {
        log.record('other', error);
      }
      expect(log.text.split('\n')[1], contains('thrower'));
    });
  });

  group('the log', () {
    late Directory directory;
    late File file;

    setUp(() {
      directory = Directory.systemTemp.createTempSync('error-log-');
      file = File('${directory.path}/diagnostics.log');
    });

    tearDown(() => directory.deleteSync(recursive: true));

    /// The words of each line of [of], without their times and stacks.
    List<String> words(File of) => [
      for (final line in of.readAsLinesSync()) line.split('\t')[1],
    ];

    test('keeps the newest first, and at most fifty', () {
      final log = ErrorLog.detached();
      for (var i = 0; i < 60; i++) {
        log.record('step $i', StateError('x'));
      }
      expect(ErrorLog.kept, 50);
      expect(log.count, 50);
      expect(log.entries.first.$2, 'step 59：StateError: Bad state: x');
      expect(log.entries.last.$2, 'step 10：StateError: Bad state: x');
    });

    test('recording writes nothing by itself: the file comes later, the '
        'problems of one moment together and in order', () async {
      final log = ErrorLog.detached()..keepIn(file);
      log.record('a', StateError('x'));
      log.record('b', StateError('x'));
      log.record('c', StateError('x'));
      // Nothing was written while recording, yet all of it can be
      // exported already.
      expect(file.existsSync(), isFalse);
      expect(log.text, contains('a：'));
      expect(log.entries.map((e) => e.$2.substring(0, 1)), ['c', 'b', 'a']);
      await log.flush();
      expect(words(file), [
        'a：StateError: Bad state: x',
        'b：StateError: Bad state: x',
        'c：StateError: Bad state: x',
      ]);
      // A later batch goes after it.
      log.record('d', StateError('x'));
      await log.flush();
      expect(words(file).last, 'd：StateError: Bad state: x');
      expect(words(file).length, 4);
    });

    testWidgets('what waits is written by itself two seconds later', (
      tester,
    ) async {
      final log = ErrorLog.detached()..keepIn(file);
      log.record('a', StateError('x'));
      // A second problem in that time does not start a second wait.
      log.record('b', StateError('x'));
      expect(ErrorLog.flushDelay, const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 1999));
      expect(file.existsSync(), isFalse);
      await tester.pump(const Duration(milliseconds: 1));
      // The write itself is real file work, off the test's made-up clock:
      // given real time, a step at a time, until the file is there.
      for (var i = 0; i < 200 && !file.existsSync(); i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump();
      }
      for (var i = 0; i < 200 && file.lengthSync() == 0; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump();
      }
      expect(words(file), [
        'a：StateError: Bad state: x',
        'b：StateError: Bad state: x',
      ]);
    });

    test('what is kept comes back after the app is closed and opened, '
        'with its stack', () async {
      final log = ErrorLog.detached()..keepIn(file);
      log.record(
        '備份',
        const FormatException('amount 12345 for 全聯'),
        StackTrace.fromString('#0      f (package:expense_tracker/a.dart:1:2)'),
      );
      await log.flush();

      // A later run reads the same file and has the line again.
      final later = ErrorLog.detached()..keepIn(file);
      expect(
        later.entries.single.$2,
        '備份：FormatException: FormatException: amount # for …',
      );
      expect(
        later.text.split('\n').last,
        '    #0 f (package:expense_tracker/a.dart:1:2)',
      );
    });

    test('a line an older version wrote is read, and cleaned now', () {
      file.writeAsStringSync(
        '2026-10-01T08:00:00.000\t備份：StateError: paid 500 to 全聯',
      );
      final log = ErrorLog.detached()..keepIn(file);
      expect(log.entries.single.$2, '備份：StateError: paid # to …');
    });

    test('the same fault again and again is counted, not kept anew', () async {
      final log = ErrorLog.detached()..keepIn(file);
      log.record('other', StateError('x'), StackTrace.empty);
      for (var i = 0; i < 120; i++) {
        log.record('畫面錯誤', StateError('y'), StackTrace.empty);
      }
      expect(log.count, 2);
      expect(log.entries.first.$2, '畫面錯誤：StateError: Bad state: y ×120');
      await log.flush();
      // Two problems and one count: three lines, not 121.
      expect(file.readAsLinesSync().length, 3);
      final later = ErrorLog.detached()..keepIn(file);
      expect(later.entries.first.$2, '畫面錯誤：StateError: Bad state: y ×120');
      expect(later.entries.last.$2, 'other：StateError: Bad state: x');
    });

    test('a full file is put aside and started again, and both are read '
        'back', () async {
      expect(ErrorLog.maxFileBytes, 131072); // 128 × 1024
      final log = ErrorLog.detached()..keepIn(file);
      // 131,050 bytes are there already: the next line, some 60 more,
      // would pass 131,072.
      file.writeAsStringSync('${'x' * 131049}\n');
      log.record('first', StateError('x'), StackTrace.empty);
      await log.flush();
      final aside = File('${file.path}.1');
      expect(aside.lengthSync(), 131050);
      expect(words(file), ['first：StateError: Bad state: x']);
      // The next one fits, and goes after it.
      log.record('second', StateError('x'), StackTrace.empty);
      await log.flush();
      expect(words(file).length, 2);

      // Filled again: the file put aside before is replaced, so there are
      // never more than two.
      file.writeAsStringSync(
        '2026-11-23T04:00:00.000Z\told：StateError: Bad state: x\n'
        '${'x' * 131000}\n',
      );
      final again = ErrorLog.detached()..keepIn(file);
      again.record('third', StateError('x'), StackTrace.empty);
      await again.flush();
      expect(
        aside.readAsLinesSync().first,
        endsWith('old：StateError: Bad state: x'),
      );
      expect(directory.listSync().length, 2);
      final later = ErrorLog.detached()..keepIn(file);
      expect(later.entries.map((e) => e.$2), [
        'third：StateError: Bad state: x',
        'old：StateError: Bad state: x',
      ]);
    });

    test('a file that cannot be written leaves the log in memory, says so, '
        'and is written once it can be', () async {
      final log = ErrorLog.detached();
      final missing = File('${directory.path}/missing/dir/diagnostics.log');
      log.keepIn(missing);
      log.record('x', StateError('y'), StackTrace.empty);
      await log.flush();
      expect(log.entries.last.$2, 'x：StateError: Bad state: y');
      expect(
        log.entries.first.$2,
        '診斷紀錄：PathNotFoundException: Cannot open file (errno 2)',
      );
      // Its folder is there now: the next write takes both along.
      missing.parent.createSync(recursive: true);
      await log.flush();
      expect(words(missing), [
        'x：StateError: Bad state: y',
        '診斷紀錄：PathNotFoundException: Cannot open file (errno 2)',
      ]);
    });

    test('an unreadable file starts the log again, and says so', () {
      file.writeAsBytesSync([0xff, 0xfe, 0x00, 0x41]);
      final log = ErrorLog.detached();
      expect(() => log.keepIn(file), returnsNormally);
      expect(log.entries.single.$2, startsWith('診斷紀錄：FileSystemException'));
    });

    test('the text to export has a line per problem, then its stack', () {
      AppClock.use(FixedClock(UtcInstant(DateTime.utc(2026, 11, 23, 4))));
      addTearDown(AppClock.reset);
      final log = ErrorLog.detached()..keepIn(file);
      log.record('a', StateError('p'), StackTrace.empty);
      log.record(
        'b',
        StateError('q'),
        StackTrace.fromString('#0      f (package:expense_tracker/a.dart:1:2)'),
      );
      final lines = log.text.split('\n');
      expect(lines.length, 3);
      expect(lines[0], endsWith('  b：StateError: Bad state: q'));
      expect(lines[1], '    #0 f (package:expense_tracker/a.dart:1:2)');
      expect(lines[2], endsWith('  a：StateError: Bad state: p'));
    });
  });
}
