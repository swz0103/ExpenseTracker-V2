import 'dart:convert';

import 'package:expense_tracker/src/core/ledger/persistence/record_version.dart';
import 'package:flutter_test/flutter_test.dart';

/// R12 F1: a `_v` that is no version any app wrote is unreadable, never
/// thrown.
void main() {
  int? versionIn(String v) =>
      versionOf(jsonDecode('{"_v":$v}') as Map<String, Object?>);

  test('a row without _v is version 1; a whole number is its version', () {
    expect(versionOf(const {}), 1);
    expect(versionIn('1'), 1);
    expect(versionIn('2'), 2);
    expect(versionIn('7'), 7);
    // A whole number written with a point is still that number.
    expect(versionIn('2.0'), 2);
  });

  test('infinite, fractional, zero or negative _v is no version', () {
    // 1e999 and 1.0e400 read as infinity; -1e999 as minus infinity.
    for (final v in [
      '1e999',
      '-1e999',
      '1.0e400',
      '2.9',
      '-5',
      '0',
      '-0.0',
      '"2"',
      'true',
      '[]',
    ]) {
      expect(versionIn(v), isNull, reason: v);
    }
  });

  test('a huge whole _v is a version far beyond this one', () {
    expect(versionIn('1e18'), 1000000000000000000);
    expect(versionIn('1e300')! > recordVersion, isTrue);
    expect(versionIn('9223372036854775807'), 9223372036854775807);
  });

  test('rowVersion throws a FormatException, never another error', () {
    expect(
      () => rowVersion(jsonDecode('{"_v":1e999}') as Map<String, Object?>),
      throwsA(isA<FormatException>()),
    );
    expect(rowVersion(const {'_v': 2}), 2);
  });
}
