/// D84: an error reaches the person as a sentence, never as itself.
library;

import 'dart:io';

import 'package:core/foundation_values.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/messages/problem_messages.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const tail = '可在診斷匯出詳細資料';

  test('a fault of the phone or the app is one sentence and the way to '
      'its details, never its own words', () {
    final faults = <Object>[
      const FileSystemException(
        'Cannot write',
        '/data/x',
        OSError('No space', 28),
      ),
      PlatformException(code: 'E42', message: 'java.io.IOException: boom'),
      const FormatException('Unexpected character'),
      StateError('x'),
    ];
    for (final fault in faults) {
      expect(describeProblem(fault), '沒有完成這個動作，$tail');
      expect(problemNote('匯出失敗', fault), '匯出失敗，$tail');
      expect(actionableProblem(fault), isNull);
    }
  });

  test('a refusal the person can act on says what to do', () {
    expect(
      problemNote('匯出失敗', PlatformException(code: 'busy')),
      '匯出失敗：上一個檔案還在處理，請稍候再試。',
    );
    expect(describeProblem(const NameTaken()), startsWith('這個分類名稱已經有了'));
    expect(
      describeProblem(const MoneyException(MoneyError.precision)),
      '金額的小數位數太多。',
    );
  });

  test('failureNote joins with a comma', () {
    expect(failureNote('沒有存成圖片'), '沒有存成圖片，可在診斷匯出詳細資料');
  });
}
