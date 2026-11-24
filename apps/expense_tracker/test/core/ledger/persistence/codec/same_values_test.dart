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

  test('a short note is shared, a long one kept as it is', () {
    final same = SameValues();
    String fresh(String text) => String.fromCharCodes(text.codeUnits);
    // 16 characters, the most shared: 早餐 and fourteen x.
    final short = '早餐${'x' * 14}';
    expect(short.length, 16);
    expect(sharedNoteLength, 16);
    final first = fresh(short);
    expect(identical(same.note(first), first), isTrue);
    expect(identical(same.note(fresh(short)), first), isTrue);
    // 17 characters: each kept as read.
    final long = '${short}y';
    final again = fresh(long);
    expect(identical(same.note(fresh(long)), again), isFalse);
    expect(identical(same.note(again), again), isTrue);
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
