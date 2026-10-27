import 'dart:io';

import 'package:expense_tracker/src/core/perf.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// What 效能與診斷 keeps of an error can be exported: it must never carry
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
      final said = Perf.describe(error);
      expect(said, kept, reason: '$error');
      expect(said, isNot(contains('/data/')));
      // Nothing the person wrote: no Chinese, only ASCII and the ellipsis.
      expect(RegExp(r'[^\x20-\x7e…]').hasMatch(said), isFalse, reason: said);
    }
  });

  test('a long message is cut to one short line', () {
    final said = Perf.describe(StateError('x' * 500 + '\nsecond line'));
    expect(said, isNot(contains('second')));
    expect(said.length, lessThan(160));
  });
}
