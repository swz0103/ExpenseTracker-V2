import 'dart:math';

import 'package:expense_tracker/src/core/ledger/models/models.dart';
import 'package:expense_tracker/src/core/ledger/repositories/entry_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fuzz/repository_fuzz.dart';

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
  repositoryFuzz();

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

    expect(entries.remove(entries.all.first), isTrue);
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

  group('once worked out, the indexes follow each change', () {
    // Ask first, so each index exists before it is changed.
    EntryRepository asked(List<Entry> entries) {
      final repository = EntryRepository(entries);
      repository.inMonth(2026, 10);
      repository.byId('a');
      repository.refundedTotal('a');
      repository.firstDate;
      return repository;
    }

    test('an entry added later on an earlier day finds its place', () {
      final entries = asked([
        _entry('a', _day(10, 5)),
        _entry('b', _day(10, 3)),
      ]);
      entries.add(_entry('c', _day(10, 4)));
      entries.add(_entry('d', _day(10, 5)));
      expect(_ids(entries.inMonth(2026, 10)), ['d', 'a', 'c', 'b']);
      expect(_ids(entries.onDay(_day(10, 5))), ['d', 'a']);
      expect(_ids(entries.onDay(_day(10, 4))), ['c']);
      expect(entries.onDay(_day(10, 6)), isEmpty);
    });

    test('a first entry in a month opens it, the last one closes it', () {
      final entries = asked([_entry('a', _day(10, 5))]);
      entries.add(_entry('n', _day(11, 1)));
      expect(_ids(entries.inMonth(2026, 11)), ['n']);
      entries.removeLast();
      expect(entries.inMonth(2026, 11), isEmpty);
    });

    test('a batch of more than sixty-four is taken as a whole', () {
      final entries = asked([_entry('a', _day(10, 5))]);
      final batch = [
        for (var i = 0; i < 80; i++) _entry('b$i', _day(10, 1 + i % 28)),
      ];
      entries.addAll(batch);
      expect(entries.inMonth(2026, 10), hasLength(81));
      expect(entries.byId('b79'), isNotNull);
      expect(entries.length, 81);
    });

    test('an entry put in place of one on the same day keeps its place', () {
      final entries = asked([
        _entry('a', _day(10, 5)),
        _entry('b', _day(10, 5)),
      ]);
      entries[0] = _entry('a2', _day(10, 5));
      expect(_ids(entries.inMonth(2026, 10)), ['b', 'a2']);
      expect(entries.byId('a'), isNull);
      expect(entries.byId('a2'), isNotNull);
    });

    test('an entry put on another day, or in another month, moves', () {
      final entries = asked([
        _entry('a', _day(10, 5)),
        _entry('b', _day(10, 5)),
      ]);
      entries[1] = _entry('b2', _day(9, 1));
      expect(_ids(entries.inMonth(2026, 10)), ['a']);
      expect(_ids(entries.inMonth(2026, 9)), ['b2']);
      entries[0] = _entry('a2', _day(10, 2));
      expect(_ids(entries.onDay(_day(10, 2))), ['a2']);
    });

    test('taking away the earliest entry moves the first date on', () {
      final entries = asked([
        _entry('a', _day(10, 5)),
        _entry('b', _day(8, 1)),
        _entry('c', _day(9, 1)),
      ]);
      expect(entries.firstDate, _day(8, 1));
      entries.remove(entries[1]);
      expect(entries.firstDate, _day(9, 1));
      entries.add(_entry('d', _day(7, 7)));
      expect(entries.firstDate, _day(7, 7));
    });

    test('refunds follow what is added, taken away and put in place', () {
      final entries = asked([
        _entry('a', _day(10, 1), amount: 500),
        _entry('r', _day(10, 2), amount: 100, refundOf: 'a'),
      ]);
      expect(entries.refundedTotal('a'), 100);
      entries.add(_entry('r2', _day(10, 3), amount: 50, refundOf: 'a'));
      expect(entries.refundedTotal('a'), 150);
      entries[1] = _entry('r', _day(10, 2), amount: 70, refundOf: 'a');
      expect(entries.refundedTotal('a'), 120);
      entries.removeAt(2);
      expect(entries.refundedTotal('a'), 70);
      entries.removeAt(1);
      expect(entries.refundedTotal('a'), 0);
    });

    test('a list handed out is a snapshot, not changed by what follows', () {
      final entries = asked([_entry('a', _day(10, 5))]);
      final before = entries.inMonth(2026, 10);
      entries.add(_entry('b', _day(10, 6)));
      expect(_ids(before), ['a']);
      expect(_ids(entries.inMonth(2026, 10)), ['b', 'a']);
    });

    test('a run of same-day replacements shows at the next ask', () {
      final entries = asked([
        for (var i = 0; i < 200; i++) _entry('e$i', _day(10, 1 + i % 28)),
      ]);
      for (var i = 0; i < 200; i += 2) {
        entries[i] = _entry('r$i', entries[i].date, amount: 7);
      }
      final month = entries.inMonth(2026, 10);
      expect(month, hasLength(200));
      expect(month.where((e) => e.id.startsWith('r')), hasLength(100));
      expect(entries.byId('e0'), isNull);
      expect(entries.byId('r0')!.amount, 7);
      // Asking again changes nothing.
      expect(_ids(entries.inMonth(2026, 10)), _ids(month));
    });

    test('an entry put in place twice stands once, as the last', () {
      final entries = asked([
        _entry('a', _day(10, 5)),
        _entry('b', _day(10, 5)),
      ]);
      entries[0] = _entry('a2', _day(10, 5));
      entries[0] = _entry('a3', _day(10, 5));
      expect(_ids(entries.inMonth(2026, 10)), ['b', 'a3']);
    });

    test('an entry put in place and then taken away is gone', () {
      final entries = asked([
        _entry('a', _day(10, 5)),
        _entry('b', _day(10, 5)),
      ]);
      entries[1] = _entry('b2', _day(10, 5));
      entries.removeAt(1);
      expect(_ids(entries.inMonth(2026, 10)), ['a']);
      entries[0] = _entry('a2', _day(10, 5));
      entries.add(_entry('c', _day(10, 6)));
      expect(_ids(entries.inMonth(2026, 10)), ['c', 'a2']);
    });

    test('removing something that is not there changes nothing', () {
      final entries = asked([_entry('a', _day(10, 5))]);
      expect(entries.remove(_entry('x', _day(10, 5))), isFalse);
      expect(entries.length, 1);
    });
  });

  group('every way the entries can be changed keeps the indexes right', () {
    // Each starts from a repository whose indexes are already worked out,
    // changes it with a list method, and checks against the list itself.
    List<Entry> fresh() => [
      for (var i = 0; i < 12; i++) _entry('e$i', _day(10, 1 + i % 3)),
    ];

    void agrees(EntryRepository entries, String how) {
      final wanted = [...entries.all.indexed]
        ..sort((a, b) {
          final byDate = b.$2.date.compareTo(a.$2.date);
          return byDate != 0 ? byDate : b.$1.compareTo(a.$1);
        });
      expect(_ids(entries.inMonth(2026, 10)), [
        for (final (_, e) in wanted) e.id,
      ], reason: how);
      for (final e in entries.all) {
        expect(entries.byId(e.id), same(e), reason: how);
      }
    }

    final changes = <String, void Function(EntryRepository)>{
      'insert': (r) => r.insert(3, _entry('x1', _day(10, 2))),
      'removeAt': (r) => r.removeAt(4),
      'removeLast': (r) => r.removeLast(),
      'removeRange': (r) => r.removeRange(1, 4),
      'removeWhere': (r) => r.removeWhere((e) => e.date.day != 2),
      'addAll': (r) =>
          r.addAll([_entry('y1', _day(10, 3)), _entry('y2', _day(10, 1))]),
      'changeAll to other days': (r) => r.changeAll(
        (e) => e.date.day == 1 ? _entry('${e.id}m', _day(10, 3)) : null,
      ),
      'reversed into place': (r) {
        final back = r.all.reversed.toList();
        for (var i = 0; i < back.length; i++) {
          r[i] = back[i];
        }
      },
      'cleared and refilled': (r) {
        final kept = [...r.all.reversed];
        r
          ..clear()
          ..addAll(kept);
      },
    };
    for (final MapEntry(key: how, value: change) in changes.entries) {
      test(how, () {
        final entries = EntryRepository(fresh());
        entries.inMonth(2026, 10);
        entries.byId('e0');
        change(entries);
        agrees(entries, how);
      });
      // All on one day, where only the place in the list orders them.
      test('$how, all on one day', () {
        final entries = EntryRepository([
          for (var i = 0; i < 12; i++) _entry('d$i', _day(10, 2)),
        ]);
        entries.inMonth(2026, 10);
        entries.byId('d0');
        change(entries);
        agrees(entries, '$how, one day');
      });
    }
  });

  for (final seed in [1, 5, 9, 31, 77, 123, 456, 789]) {
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

      for (var step = 0; step < 300; step++) {
        final label = 'seed $seed step $step';
        switch (random.nextInt(14)) {
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
          case 12 || 13 when plain.isNotEmpty:
            final at = random.nextInt(plain.length);
            final old = plain[at];
            final e = _entry(
              's${serial++}',
              old.date,
              amount: 5 + random.nextInt(9),
            );
            entries[at] = e;
            plain[at] = e;
          case 10:
            final batch = [for (var i = 0; i < 70; i++) make()];
            entries.addAll(batch);
            plain.addAll(batch);
          case 11 when plain.isNotEmpty:
            final e = plain[random.nextInt(plain.length)];
            expect(entries.remove(e), isTrue);
            plain.remove(e);
          case 9:
            final month = 1 + random.nextInt(4);
            entries.removeWhere((e) => e.date.month == month);
            plain.removeWhere((e) => e.date.month == month);
        }
        compare(label);
      }
    });
  }

  group('accounts, groups, refunds and written order follow too', () {
    // Ordered the slow way from the plain list.
    List<(int, Entry)> byDay(List<Entry> plain, {required bool newest}) =>
        [...plain.indexed]..sort((a, b) {
          final byDate = a.$2.date.compareTo(b.$2.date);
          final order = byDate != 0 ? byDate : a.$1.compareTo(b.$1);
          return newest ? -order : order;
        });

    for (final seed in [2, 3, 11, 42, 99, 314]) {
      test('they answer like a list worked through the slow way ($seed)', () {
        final random = Random(seed);
        final entries = EntryRepository();
        final plain = <Entry>[];
        var serial = 0;
        const accounts = ['a', 'b', 'c'];

        Entry make({String? id, DateTime? date}) {
          final transfer = random.nextInt(4) == 0;
          return Entry(
            id: id ?? 'e${serial++}',
            date: date ?? _day(1 + random.nextInt(3), 1 + random.nextInt(4)),
            type: transfer ? EntryType.transfer : EntryType.expense,
            amount: 10 + random.nextInt(90),
            account: accounts[random.nextInt(3)],
            to: transfer ? accounts[random.nextInt(3)] : null,
            refundOf: plain.isNotEmpty && random.nextInt(5) == 0
                ? plain[random.nextInt(plain.length)].id
                : null,
            group: random.nextInt(4) == 0 ? 'g${random.nextInt(4)}' : null,
          );
        }

        void compare(String step) {
          expect(_ids(entries.all), _ids(plain), reason: step);
          expect(
            [for (final month in entries.newestMonths) ..._ids(month)],
            [for (final (_, e) in byDay(plain, newest: true)) e.id],
            reason: '$step newest months',
          );
          for (final account in [...accounts, 'none']) {
            expect(_ids(entries.ofAccount(account)), [
              for (final (_, e) in byDay(plain, newest: false))
                if (e.account == account || e.to == account) e.id,
            ], reason: '$step account $account');
          }
          for (var g = 0; g < 4; g++) {
            expect(_ids(entries.inGroup('g$g')), [
              for (final e in plain)
                if (e.group == 'g$g') e.id,
            ], reason: '$step group g$g');
          }
          for (final e in plain) {
            expect(_ids(entries.refundsOf(e.id)), [
              for (final r in plain)
                if (r.refundOf == e.id) r.id,
            ], reason: '$step refunds of ${e.id}');
          }
          final some = [
            for (final e in plain.reversed)
              if (random.nextBool()) e,
          ];
          expect(_ids(entries.written(some)), [
            for (final e in plain)
              if (some.contains(e)) e.id,
          ], reason: '$step written');
        }

        for (var step = 0; step < 250; step++) {
          final label = 'seed $seed step $step';
          switch (random.nextInt(9)) {
            case 0 || 1:
              final e = make();
              entries.add(e);
              plain.add(e);
            case 2:
              final at = random.nextInt(plain.length + 1);
              final e = make();
              entries.insert(at, e);
              plain.insert(at, e);
            case 3 when plain.isNotEmpty:
              // The same entry moved to another day.
              final at = random.nextInt(plain.length);
              final e = make(id: plain[at].id);
              entries[at] = e;
              plain[at] = e;
            case 4 when plain.isNotEmpty:
              // The same entry changed on its own day.
              final at = random.nextInt(plain.length);
              final e = make(id: plain[at].id, date: plain[at].date);
              entries[at] = e;
              plain[at] = e;
            case 5 when plain.isNotEmpty:
              final gone = {
                for (var i = 0; i < 1 + random.nextInt(12); i++)
                  plain[random.nextInt(plain.length)],
              };
              final removed = entries.removeEach(gone);
              final wanted = [
                for (final (i, e) in plain.indexed)
                  if (gone.contains(e)) (i, e),
              ];
              expect(removed, wanted, reason: label);
              plain.removeWhere(gone.contains);
              // Put back where they were, as an undo does, now and then.
              if (random.nextBool()) {
                for (final (i, e) in removed) {
                  entries.insert(i, e);
                  plain.insert(i, e);
                }
              }
            case 6 when plain.isNotEmpty:
              final at = random.nextInt(plain.length);
              expect(entries.removeAt(at), plain.removeAt(at));
            case 7:
              final batch = [for (var i = 0; i < 3; i++) make()];
              entries.addAll(batch);
              plain.addAll(batch);
            case 8 when plain.length > 1:
              final day = plain[random.nextInt(plain.length)].date;
              entries.removeWhere((e) => e.date == day);
              plain.removeWhere((e) => e.date == day);
          }
          compare(label);
        }
      });
    }

    test('a delete, an undo and a date move keep every index', () {
      Entry on(String id, String account, DateTime date) => Entry(
        id: id,
        date: date,
        type: EntryType.expense,
        amount: 100,
        account: account,
      );
      final entries = EntryRepository([
        for (var i = 0; i < 300; i++)
          on('e$i', i.isEven ? 'a' : 'b', _day(1 + i % 6, 1 + i % 20)),
      ]);
      entries.inMonth(2026, 1);
      entries.ofAccount('a');
      entries.byId('e0');
      final a = entries.versionOf('a');
      final months = entries.inMonth(2026, 1);

      // Odd entries are on b: a's version is not moved by them, and the
      // months they are not in are the very lists handed out before.
      final removed = entries.removeEach([entries[1], entries[13]]);
      expect(removed.map((r) => r.$1), [1, 13]);
      for (final (i, e) in removed) {
        entries.insert(i, e);
      }
      entries[25] = on('e25', 'b', _day(6, 28));
      expect(entries.versionOf('a'), a, reason: 'nothing of a changed');
      expect(entries.inMonth(2026, 1), same(months));
      expect(_ids(entries.onDay(_day(6, 28))), ['e25']);
      expect(entries.ofAccount('b').last.id, 'e25');
    });
  });

  test('an account\'s version moves with its own entries only', () {
    Entry at(String id, String account, {String? to}) => Entry(
      id: id,
      date: _day(10, 1),
      type: to == null ? EntryType.expense : EntryType.transfer,
      amount: 100,
      account: account,
      to: to,
    );
    final entries = EntryRepository([at('x', 'a')]);
    final a = entries.versionOf('a');
    final b = entries.versionOf('b');
    final c = entries.versionOf('c');

    entries.add(at('y', 'a'));
    expect(entries.versionOf('a'), isNot(a));
    expect(entries.versionOf('b'), b, reason: 'not touched');

    // A transfer moves both ends.
    final a2 = entries.versionOf('a');
    entries.add(at('t', 'b', to: 'c'));
    expect(entries.versionOf('b'), isNot(b));
    expect(entries.versionOf('c'), isNot(c));
    expect(entries.versionOf('a'), a2);

    // Moved from one account to another: both.
    final b2 = entries.versionOf('b');
    final a3 = entries.versionOf('a');
    entries[0] = at('x', 'b');
    expect(entries.versionOf('a'), isNot(a3));
    expect(entries.versionOf('b'), isNot(b2));

    // Taken away.
    final a4 = entries.versionOf('a');
    entries.removeLast();
    entries.removeAt(entries.length - 1);
    expect(entries.versionOf('a'), isNot(a4));

    // A change not followed entry by entry moves every account.
    final before = {
      for (final k in ['a', 'b', 'c', 'd']) k: entries.versionOf(k),
    };
    // (More added at once than are followed one by one.)
    entries.addAll([for (var i = 0; i < 65; i++) at('m$i', 'z')]);
    for (final MapEntry(:key, :value) in before.entries) {
      expect(entries.versionOf(key), isNot(value), reason: key);
    }
  });

  group('order written', () {
    test('D75: each entry keeps its place, read as kept or in turn', () {
      final kept = EntryRepository(
        [_entry('a', _day(10, 1)), _entry('b', _day(10, 1))],
        {'a': 10, 'b': 20},
      );
      expect((kept.orderOf('a'), kept.orderOf('b')), (10, 20));
      kept.add(_entry('c', _day(10, 1)));
      // After the last kept: 20 + 1.
      expect(kept.orderOf('c'), 21);
      final plain = EntryRepository([_entry('x', _day(10, 1))]);
      expect(plain.orderOf('x'), 0);
    });

    test('D75: an entry taken away comes back to its own place', () {
      final entries = EntryRepository([
        for (final id in ['a', 'b', 'c', 'd']) _entry(id, _day(10, 1)),
      ]);
      final b = entries.removeAt(1);
      entries.add(_entry('e', _day(10, 1)));
      entries.restoreAt(b, entries.orderOf('b'));
      expect(_ids(entries.all), ['a', 'b', 'c', 'd', 'e']);
      expect(_ids(entries.onDay(_day(10, 1))), ['e', 'd', 'c', 'b', 'a']);
      // The place after every other: last, the newest of its day.
      final e = entries.removeAt(4);
      entries.restoreAt(e, 4);
      expect(_ids(entries.onDay(_day(10, 1))).first, 'e');
      // No place known: last.
      entries.restoreAt(_entry('f', _day(10, 1)), null);
      expect(entries.all.last.id, 'f');
    });

    test('D75: a place held in the trash is never given to a new entry', () {
      final entries = EntryRepository([_entry('a', _day(10, 1))]);
      entries.reserve(7, id: 'trashed');
      expect(entries.orderOf('trashed'), 7);
      entries.add(_entry('b', _day(10, 1)));
      expect(entries.orderOf('b'), 8);
      final copy = EntryRepository()..replaceWith(entries);
      expect(_ids(copy.all), ['a', 'b']);
      expect(copy.orderOf('b'), 8);
    });

    test('D76: newest first by day, then the later written first', () {
      final entries = EntryRepository(
        [
          _entry('early', _day(10, 2)),
          _entry('late', _day(10, 2)),
          _entry('old', _day(10, 1)),
        ],
        {'early': 1, 'late': 2, 'old': 3},
      );
      final shuffled = [entries.all[0], entries.all[2], entries.all[1]];
      expect(_ids(shuffled..sort(newestFirst(entries))), [
        'late',
        'early',
        'old',
      ]);
    });
  });
}
