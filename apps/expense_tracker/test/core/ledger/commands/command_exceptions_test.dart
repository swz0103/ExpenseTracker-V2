/// Checks the ledger's problems: each says which it is when logged, a
/// failure carries what the data source threw, and a screen tells every
/// one of them apart in words.
library;

import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/messages/problem_messages.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final cause = Exception('disk full');
  final problems = <LedgerProblem>[
    SharesShort(),
    const NameTaken(),
    KeepFailed(cause),
    ReloadFailed(cause),
    RecordRefused(const [MissingDestination(), SameAccountTransfer()]),
  ];

  test('each problem names itself in the log, with its cause', () {
    expect(problems.map((p) => '$p'), [
      'SharesShort',
      'NameTaken',
      'KeepFailed(Exception: disk full)',
      'ReloadFailed(Exception: disk full)',
      'RecordRefused(MissingDestination, SameAccountTransfer)',
    ]);
  });

  test('a failure keeps what the data source threw', () {
    expect(KeepFailed(cause).cause, same(cause));
    expect(ReloadFailed(cause).cause, same(cause));
  });

  test('every problem is an exception told in its own words', () {
    for (final p in problems) {
      expect(p, isA<Exception>());
    }
    final words = problems.map(describeProblem).toSet();
    expect(words, hasLength(problems.length));
    expect(describeProblem(ReloadFailed(cause)), contains('重新打開 App'));
    // A refused record says its first reason, as the form would.
    expect(describeProblem(problems.last), '請選擇轉入帳戶');
  });

  test('a refusal carries at least one reason', () {
    expect(() => RecordRefused(const []), throwsArgumentError);
  });
}
