import 'package:expense_tracker/src/core/ledger/persistence/codec/same_values.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('an equal text met again is the one met first', () {
    final same = SameValues();
    final first = String.fromCharCodes('bank'.codeUnits);
    final again = String.fromCharCodes('bank'.codeUnits);
    expect(identical(first, again), isFalse);
    expect(identical(same.text(first), first), isTrue);
    expect(identical(same.text(again), first), isTrue);
  });

  test('a day is made once for its text', () {
    final same = SameValues();
    var made = 0;
    DateTime parse(String text) {
      made++;
      final [y, m, d] = [for (final p in text.split('-')) int.parse(p)];
      return DateTime.utc(y, m, d);
    }

    final day = same.day('2026-10-04', parse);
    expect(day, DateTime.utc(2026, 10, 4));
    expect(identical(same.day('2026-10-04', parse), day), isTrue);
    same.day('2026-10-05', parse);
    // Two texts, two days made.
    expect(made, 2);
  });
}
