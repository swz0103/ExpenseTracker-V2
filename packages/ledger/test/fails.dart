import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:test/test.dart';

/// Throws a [LedgerException] with exactly [code], so a test fails when a
/// different rule rejects the input.
Matcher fails(LedgerError code) =>
    throwsA(isA<LedgerException>().having((error) => error.code, 'code', code));

/// Throws a [MoneyException] for an amount out of range.
final overflows = throwsA(
  isA<MoneyException>().having((e) => e.code, 'code', MoneyError.overflow),
);
