import 'dart:io';

import 'package:expense_tracker/src/core/diagnostics/error_log.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// What the error log keeps of an error can be exported: it must never carry
/// what the person wrote, amounts, or where their files are.
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
    expect(said.length, lessThan(160));
  });

  group('the log', () {
    late Directory directory;
    late File file;

    setUp(() {
      directory = Directory.systemTemp.createTempSync('error-log-');
      file = File('${directory.path}/diagnostics.log');
    });

    tearDown(() => directory.deleteSync(recursive: true));

    test('keeps the newest first, and at most fifty', () {
      final log = ErrorLog.instance;
      log.keepIn(File('${directory.path}/none.log'));
      final before = log.count;
      for (var i = 0; i < 60; i++) {
        log.record('step $i', StateError('x'));
      }
      expect(log.count, 50);
      expect(log.entries.first.$2, startsWith('step 59'));
      expect(log.entries.last.$2, startsWith('step 10'));
      expect(before, lessThanOrEqualTo(50));
    });

    test('what is kept comes back after the app is closed and opened', () {
      final log = ErrorLog.instance;
      log.keepIn(file);
      log.record('備份', const FormatException('amount 12345 for 全聯'));
      expect(file.existsSync(), isTrue);
      // The file holds the cleaned words, never the person's own. Only
      // the words after each line's time are looked at: a time's own
      // digits may hold 12345.
      final words = [
        for (final line in file.readAsLinesSync()) line.split('\t').last,
      ].join('\n');
      expect(words, isNot(contains('全聯')));
      expect(words, isNot(contains('12345')));

      // A later run reads the same file and has the line again.
      log.keepIn(file);
      expect(log.entries.any((e) => e.$2.startsWith('備份：')), isTrue);
    });

    test('a file that cannot be written leaves the log in memory', () {
      final log = ErrorLog.instance;
      log.keepIn(File('${directory.path}/missing/dir/diagnostics.log'));
      expect(() => log.record('x', StateError('y')), returnsNormally);
      expect(log.entries.first.$2, startsWith('x：'));
    });

    test('an unreadable file starts the log again, with no error', () {
      file.writeAsBytesSync([0xff, 0xfe, 0x00, 0x41]);
      expect(() => ErrorLog.instance.keepIn(file), returnsNormally);
    });

    test('the text to export has one line per problem', () {
      final log = ErrorLog.instance..keepIn(file);
      log.record('a', StateError('1'));
      log.record('b', StateError('2'));
      final lines = log.text.split('\n');
      expect(lines.length, log.count);
      expect(lines.first, contains('  b：'));
    });
  });
}
