import 'dart:convert';
import 'dart:io';

import 'package:core/app_core.dart';
import 'package:core/foundation_values.dart';
import 'package:domain/credit_cards.dart';
import 'package:domain/data_exchange.dart';
import 'package:ledger_trade_costs/model/trade_values.dart';
import 'package:storage/storage.dart';
import 'package:vault/backup_security.dart';
import 'package:vault/ledger_backup.dart';
import 'package:vault/ledger_vault.dart';
import 'package:expense_tracker/src/core/diagnostics/error_log.dart';
import 'package:expense_tracker/src/core/ledger/commands/command_exceptions.dart';
import 'package:expense_tracker/src/core/ledger/persistence/ledger_data_source.dart';
import 'package:expense_tracker/src/core/ledger/persistence/quarantine.dart';
import 'package:expense_tracker/src/core/platform/startup_state.dart';
import 'package:expense_tracker/src/features/backup/model/drive_backup.dart';
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
      // An exception not the app's keeps its type alone (review 33).
      const FormatException('amount 12345 for 全聯'): 'FormatException',
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

  group('review 33: what is kept is an allow-list', () {
    test('an exception not the app\'s keeps its type, never its words', () {
      expect(
        ErrorLog.describe(
          Exception('The user alice@example.com has no access'),
        ),
        '_Exception',
      );
      expect(
        ErrorLog.describe(const HttpException('Connection closed', uri: null)),
        'HttpException',
      );
      expect(
        ErrorLog.describe(const SocketException('token expired for John Chen')),
        'SocketException',
      );
    });

    test("Drive's refusal keeps its status and reason code, never its "
        'sentence', () {
      // The body Drive sends with a 403.
      const body =
          '{"error":{"code":403,"message":"The user alice@example.com does '
          'not have sufficient permissions for file 王小明的帳本.etbk.",'
          '"errors":[{"domain":"global","reason":"insufficientPermissions",'
          '"message":"The user alice@example.com does not have sufficient '
          'permissions."}]}}';
      final said = ErrorLog.describe(
        DriveException(DriveProblem.refused, DriveBackup.detailOf(403, body)),
      );
      expect(
        said,
        'DriveException: DriveException(refused, HTTP 403 '
        'insufficientPermissions)',
      );
      expect(said, isNot(contains('alice')));
      expect(said, isNot(contains('example')));
    });

    test('an address, a query and a token are taken out of words kept', () {
      expect(
        ErrorLog.describe(StateError('sent to alice@example.com today')),
        'StateError: Bad state: sent to … today',
      );
      expect(
        ErrorLog.describe(StateError('fetch https://x.io/a?token=abc failed')),
        'StateError: Bad state: fetch … failed',
      );
      expect(
        ErrorLog.describe(
          StateError('key ya29.a0AfB_byC3xKq9ZLmN0pQ2rS4tU6vW8 refused'),
        ),
        'StateError: Bad state: key ya#.… refused',
      );
      // Words the app passed itself (a delivery the job noted).
      expect(ErrorLog.describe('雲端硬碟：bob@example.org 403'), 'String: … #');
    });

    test('R34: a socket or TLS fault keeps its errno, never its words', () {
      expect(
        ErrorLog.describe(
          const SocketException(
            'Failed host lookup: www.googleapis.com',
            osError: OSError('No address associated with hostname', 7),
          ),
        ),
        'SocketException (errno 7)',
      );
      expect(
        ErrorLog.describe(
          const SocketException(
            'Connection refused',
            osError: OSError('Connection refused', 111),
          ),
        ),
        'SocketException (errno 111)',
      );
      expect(
        ErrorLog.describe(
          const HandshakeException(
            'CERTIFICATE_VERIFY_FAILED',
            OSError('unable to get local issuer certificate', 20),
          ),
        ),
        'HandshakeException (errno 20)',
      );
      expect(
        ErrorLog.describe(const HandshakeException('x')),
        'HandshakeException',
      );
    });

    test("R34: the app's own packages' exceptions keep their fixed words", () {
      expect(
        ErrorLog.describe(
          const BackupException(BackupProblem.invalidFormat, 'tail'),
        ),
        'BackupException: BackupException(invalidFormat tail)',
      );
      expect(
        ErrorLog.describe(const VaultException(VaultProblem.missingDatabase)),
        'VaultException: VaultException(missingDatabase)',
      );
      expect(
        ErrorLog.describe(const KeyringException(KeyringError.noSuchSlot)),
        'KeyringException: KeyringException(noSuchSlot)',
      );
      expect(
        ErrorLog.describe(const StorageUnavailable(StorageProblem.damaged)),
        'StorageUnavailable: StorageUnavailable(damaged)',
      );
      expect(
        ErrorLog.describe(const MoneyException(MoneyError.precision)),
        'MoneyException: MoneyException(precision)',
      );
      expect(
        ErrorLog.describe(const FxException(FxError.currencyMismatch)),
        'FxException: FxException(currencyMismatch)',
      );
      expect(
        ErrorLog.describe(
          const CreditCardException(CreditCardError.invalidInput),
        ),
        'CreditCardException: CreditCardException(invalidInput)',
      );
      expect(
        ErrorLog.describe(
          const InvestmentException(InvestmentError.fractionalShares),
        ),
        'InvestmentException: InvestmentException(fractionalShares)',
      );
      // The CSV reader's own words, the line a number like any other.
      expect(
        ErrorLog.describe(const CsvFormatException('A quote never closed', 12)),
        'CsvFormatException: A quote never closed',
      );
    });

    test("an app fault keeps its own words, and what carries another's "
        "keeps only that one's type", () {
      expect(
        ErrorLog.describe(const UnlockDelayed(Duration(seconds: 30))),
        'UnlockDelayed: UnlockDelayed',
      );
      expect(
        ErrorLog.describe(
          DataSourceException(Exception('row of alice@example.com')),
        ),
        'DataSourceException(_Exception)',
      );
      expect(
        ErrorLog.describe(
          KeepFailed(DataSourceException(const RowSetAside('entries'))),
        ),
        'KeepFailed(DataSourceException(RowSetAside: RowSetAside(entries)))',
      );
    });
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
    final line = jsonDecode(kept) as Map<String, Object?>;
    expect(
      line['what'],
      '記一筆：StateError: Bad state: Cannot save # for … in … …',
    );
    expect(line['frames'], [
      '#0 Ledger.save (package:expense_tracker/src/ledger.dart:12:5)',
    ]);
    // Nothing else is in the file: when, what, where.
    expect(line.keys, ['at', 'what', 'frames']);
    for (final secret in ['98765', '王小明', '生日', '全聯', 'sdcard', '秘密']) {
      expect(kept, isNot(contains(secret)), reason: secret);
    }
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
      for (final line in of.readAsLinesSync())
        (jsonDecode(line) as Map<String, Object?>)['what']! as String,
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
      expect(later.entries.single.$2, '備份：FormatException');
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

    test('a line cut short by a crash costs only itself', () {
      file.writeAsStringSync(
        '{"at":"2026-11-23T04:00:00.000Z","what":"a：StateError: x","frames":[]}\n'
        '{"at":"2026-11-23T04:00:01.000Z","what":"b：Sta\n'
        '{"at":"2026-11-23T04:00:02.000Z","what":"c：StateError: x","frames":[]}\n',
      );
      final log = ErrorLog.detached()..keepIn(file);
      expect(log.entries.map((e) => e.$2.substring(0, 2)), ['診斷', 'c：', 'a：']);
    });

    test('what is written after a file that ends part way through a line '
        'starts on a line of its own', () async {
      file.writeAsStringSync(
        '{"at":"2026-11-23T04:00:00.000Z","what":"a：StateError: x","frames":[]}\n'
        '{"at":"2026-11-23T04:00:01.000Z","what":"b：Sta',
      );
      final log = ErrorLog.detached()..keepIn(file);
      log.record('c', StateError('x'), StackTrace.empty);
      await log.flush();
      log.record('d', StateError('x'), StackTrace.empty);
      await log.flush();
      // What this run wrote began on a new line after the cut one, so the
      // next run reads every whole line.
      final later = ErrorLog.detached()..keepIn(file);
      expect(later.entries.map((e) => e.$2.substring(0, 2)), [
        // Reading the cut line again, this run.
        '診斷',
        'd：',
        'c：',
        // The fault of reading it, kept by the run before.
        '診斷',
        'a：',
      ]);
      // No blank line was left by the second write.
      expect(file.readAsLinesSync().where((l) => l.isEmpty), isEmpty);
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
      expect(file.readAsLinesSync().last, endsWith(',"times":120}'));
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
        '{"at":"2026-11-23T04:00:00.000Z",'
        '"what":"old：StateError: Bad state: x","frames":[]}\n'
        '${'x' * 131000}\n',
      );
      final again = ErrorLog.detached()..keepIn(file);
      again.record('third', StateError('x'), StackTrace.empty);
      await again.flush();
      expect(
        aside.readAsLinesSync().first,
        contains('old：StateError: Bad state: x'),
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
