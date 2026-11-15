import 'dart:math';

import 'package:expense_tracker/src/core/ledger/models/models.dart';
import 'package:expense_tracker/src/core/ledger/repositories/entry_repository.dart';
import 'package:flutter_test/flutter_test.dart';

Entry _entry(
  String id,
  DateTime date, {
  int amount = 100,
  String? refundOf,
  EntryType type = EntryType.expense,
}) => Entry(
  id: id,
  date: date,
  type: type,
  amount: amount,
  account: 'a',
  refundOf: refundOf,
);

DateTime _day(int month, int day) => DateTime.utc(2026, month, day);

List<String> _ids(Iterable<Entry> entries) => [for (final e in entries) e.id];

void main() {
  test('an empty repository answers with nothing', () {
    final entries = EntryRepository();
    expect(entries.isEmpty, isTrue);
    expect(entries.length, 0);
    expect(entries.byId('x'), isNull);
    expect(entries.inMonth(2026, 10), isEmpty);
    expect(entries.onDay(_day(10, 4)), isEmpty);
    expect(entries.firstDate, isNull);
    expect(entries.refundedTotal('x'), 0);
  });

  test(
    'a month lists the newest day first, the last written first in a day',
    () {
      final entries = EntryRepository([
        _entry('a', _day(10, 3)),
        _entry('b', _day(10, 4)),
        _entry('c', _day(10, 3)),
        _entry('d', _day(9, 30)),
        _entry('e', _day(10, 4)),
      ]);
      expect(_ids(entries.inMonth(2026, 10)), ['e', 'b', 'c', 'a']);
      expect(_ids(entries.inMonth(2026, 9)), ['d']);
      expect(_ids(entries.onDay(_day(10, 4))), ['e', 'b']);
      expect(_ids(entries.all), ['a', 'b', 'c', 'd', 'e']);
    },
  );

  test('the first date is the earliest, wherever it was written', () {
    final entries = EntryRepository([
      _entry('a', _day(10, 3)),
      _entry('b', _day(8, 1)),
    ]);
    expect(entries.firstDate, _day(8, 1));
  });

  test('refunds are summed against the entry they refund', () {
    final entries = EntryRepository([
      _entry('buy', _day(10, 1), amount: 1000),
      _entry('r1', _day(10, 2), amount: 200, refundOf: 'buy'),
      _entry('r2', _day(10, 3), amount: 300, refundOf: 'buy'),
      _entry('other', _day(10, 3)),
    ]);
    expect(entries.refundedTotal('buy'), 500);
    expect(entries.refundedTotal('other'), 0);
  });

  test('what was asked is worked out again after every kind of change', () {
    final entries = EntryRepository([_entry('a', _day(10, 3))]);
    expect(entries.inMonth(2026, 10), hasLength(1));
    expect(entries.byId('b'), isNull);

    entries.add(_entry('b', _day(10, 3)));
    expect(_ids(entries.inMonth(2026, 10)), ['b', 'a']);
    expect(entries.byId('b'), isNotNull);

    entries.insert(0, _entry('c', _day(10, 3)));
    expect(_ids(entries.inMonth(2026, 10)), ['b', 'a', 'c']);

    entries[0] = _entry('c2', _day(9, 1));
    expect(entries.byId('c'), isNull);
    expect(_ids(entries.inMonth(2026, 9)), ['c2']);
    expect(entries.firstDate, _day(9, 1));

    entries.removeAt(0);
    expect(entries.byId('c2'), isNull);
    expect(entries.firstDate, _day(10, 3));

    entries.removeLast();
    expect(_ids(entries.all), ['a']);

    entries.addAll([_entry('x', _day(10, 5)), _entry('y', _day(10, 6))]);
    entries.removeWhere((e) => e.id == 'x');
    expect(_ids(entries.inMonth(2026, 10)), ['y', 'a']);

    entries.removeRange(0, 1);
    expect(_ids(entries.all), ['y']);

    expect(entries.remove(entries.first), isTrue);
    expect(entries.isEmpty, isTrue);
    expect(entries.inMonth(2026, 10), isEmpty);

    entries.add(_entry('z', _day(1, 1)));
    entries.clear();
    expect(entries.byId('z'), isNull);
    expect(entries.firstDate, isNull);
  });

  test('the list of entries given is copied, not shared', () {
    final given = [_entry('a', _day(10, 3))];
    final entries = EntryRepository(given);
    given.add(_entry('b', _day(10, 3)));
    expect(entries.length, 1);
  });

  test('the view for the screens cannot be changed', () {
    final entries = EntryRepository([_entry('a', _day(10, 3))]);
    expect(
      () => entries.all.add(_entry('b', _day(10, 3))),
      throwsUnsupportedError,
    );
    expect(
      () => entries.inMonth(2026, 10).add(_entry('b', _day(10, 3))),
      throwsUnsupportedError,
    );
  });

  for (final seed in [1, 5, 9, 31, 77]) {
    test('it answers like a list worked through the slow way ($seed)', () {
      final random = Random(seed);
      final entries = EntryRepository();
      final plain = <Entry>[];
      var serial = 0;

      Entry make() => _entry(
        'e${serial++}',
        _day(1 + random.nextInt(4), 1 + random.nextInt(5)),
        amount: 10 + random.nextInt(90),
        refundOf: plain.isNotEmpty && random.nextInt(5) == 0
            ? plain[random.nextInt(plain.length)].id
            : null,
      );

      void compare(String step) {
        expect(_ids(entries.all), _ids(plain), reason: step);
        for (var month = 1; month <= 4; month++) {
          final wanted =
              [...plain.indexed.where((p) => p.$2.date.month == month)]
                ..sort((a, b) {
                  final byDate = b.$2.date.compareTo(a.$2.date);
                  return byDate != 0 ? byDate : b.$1.compareTo(a.$1);
                });
          expect(_ids(entries.inMonth(2026, month)), [
            for (final (_, e) in wanted) e.id,
          ], reason: '$step month $month');
          for (var day = 1; day <= 5; day++) {
            expect(_ids(entries.onDay(_day(month, day))), [
              for (final (_, e) in wanted)
                if (e.date.day == day) e.id,
            ], reason: '$step $month/$day');
          }
        }
        for (final e in plain) {
          expect(entries.byId(e.id), same(e), reason: step);
        }
        final first = plain.isEmpty
            ? null
            : plain.map((e) => e.date).reduce((a, b) => a.isBefore(b) ? a : b);
        expect(entries.firstDate, first, reason: step);
        for (final e in plain) {
          final refunded = plain
              .where((r) => r.refundOf == e.id)
              .fold(0, (sum, r) => sum + r.amount);
          expect(entries.refundedTotal(e.id), refunded, reason: step);
        }
      }

      for (var step = 0; step < 150; step++) {
        final label = 'seed $seed step $step';
        switch (random.nextInt(10)) {
          case 0 || 1 || 2:
            final e = make();
            entries.add(e);
            plain.add(e);
          case 3:
            final batch = [for (var i = 0; i < 3; i++) make()];
            entries.addAll(batch);
            plain.addAll(batch);
          case 4:
            final at = random.nextInt(plain.length + 1);
            final e = make();
            entries.insert(at, e);
            plain.insert(at, e);
          case 5 when plain.isNotEmpty:
            final at = random.nextInt(plain.length);
            expect(entries.removeAt(at), plain.removeAt(at));
          case 6 when plain.isNotEmpty:
            expect(entries.removeLast(), plain.removeLast());
          case 7 when plain.isNotEmpty:
            final at = random.nextInt(plain.length);
            final e = make();
            entries[at] = e;
            plain[at] = e;
          case 8 when plain.length > 1:
            final from = random.nextInt(plain.length - 1);
            final to = from + 1 + random.nextInt(plain.length - from - 1);
            entries.removeRange(from, to);
            plain.removeRange(from, to);
          case 9:
            final month = 1 + random.nextInt(4);
            entries.removeWhere((e) => e.date.month == month);
            plain.removeWhere((e) => e.date.month == month);
        }
        compare(label);
      }
    });
  }
}
