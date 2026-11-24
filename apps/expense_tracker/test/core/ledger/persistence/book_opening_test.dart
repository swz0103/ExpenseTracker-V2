import 'dart:convert';

import 'package:expense_tracker/src/core/ledger/persistence/book_opening.dart';
import 'package:expense_tracker/src/core/ledger/persistence/quarantine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storage/storage.dart';

import 'book_opening_fuzz.dart';

/// R12 F1–F3: every row a book can hold is read or set aside with why;
/// reading the book never throws, and never keeps a record the restore of
/// a backup would refuse.
void main() {
  group('mutated books', bookOpeningFuzz);

  final today = DateTime.utc(2026, 10, 4);

  String entry(String id, [Map<String, Object?> extra = const {}]) =>
      jsonEncode({
        'id': id,
        'date': '2026-09-04',
        'type': 'expense',
        'amount': 5,
        'account': 'cash',
        ...extra,
      });

  DecodedBook decode(List<(String, String, String)> rows) {
    var seq = 0;
    return decodeBook(
      shelvesOf([
        for (final (shelf, id, body) in rows) StoredRow(++seq, shelf, id, body),
      ]),
      today: today,
    );
  }

  Map<String, String> asideOf(DecodedBook book) => {
    for (final row in book.aside) row.key: row.detail,
  };

  test('entries decoded apart read as those decoded with the book', () {
    var seq = 0;
    final rows = [
      StoredRow(++seq, 'entry', 'a', entry('a')),
      StoredRow(++seq, 'entry', 'bad', 'not json'),
      StoredRow(++seq, 'entry', 'b', entry('b', {'note': '午餐'})),
      StoredRow(++seq, 'entry', 'new', '{"_v":99,${entry('new').substring(1)}'),
      StoredRow(++seq, 'entry', 'c', entry('c')),
      StoredRow(++seq, 'budget', 'x', 'not json'),
    ];
    final shelves = shelvesOf(rows);
    final whole = decodeBook(shelves, today: today);
    // The entries decoded in two parts, as a large book opens: the head
    // on the opening's worker, the tail on another.
    final entryRows = shelves['entry']!;
    final head = decodeRows(entryRows.sublist(0, 2));
    final tail = decodeRows(entryRows.sublist(2));
    final apart = decodeBook(
      shelves,
      today: today,
      entryTail: (
        records: [...head.records, ...tail.records],
        aside: [...head.aside, ...tail.aside],
      ),
    );
    expect(apart.entries.map((e) => e.id), ['a', 'b', 'c']);
    expect(whole.entries.map((e) => e.id), ['a', 'b', 'c']);
    // Each entry beside its row's place: rows 1, 3 and 5.
    expect(apart.entryPlaces, [1, 3, 5]);
    expect(whole.entryPlaces, [1, 3, 5]);
    // Set aside in the same order: the entries' rows, then the budget's.
    const order = ['entry/bad', 'entry/new', 'budget/x'];
    expect(apart.aside.map((r) => r.key), order);
    expect(whole.aside.map((r) => r.key), order);
    // A tail of only the last rows leaves the rest to the book.
    final onlyTail = decodeBook(shelves, today: today, entryTail: tail);
    expect(onlyTail.entries.map((e) => e.id), ['a', 'b', 'c']);
    expect(onlyTail.aside.map((r) => r.key), order);
  });

  test('a _v that is no version sets its row aside (F1)', () {
    final book = decode([
      for (final (i, v) in [
        '1e999',
        '-1e999',
        '1.0e400',
        '2.9',
        '-5',
        '0',
      ].indexed)
        ('entry', 'v$i', '{"_v":$v,${entry('v$i').substring(1)}'),
      ('entry', 'ok', entry('ok')),
    ]);
    expect(book.entries.map((e) => e.id), ['ok']);
    expect(asideOf(book), {
      for (var i = 0; i < 6; i++) 'entry/v$i': '_v is not a version',
    });
    expect(book.aside.map((r) => r.reason).toSet(), {QuarantineReason.invalid});
  });

  test('a record no app would write is set aside by its shape (F2, F3)', () {
    final book = decode([
      (
        'entry',
        'buy',
        entry('buy', {'type': 'buy', 'holding': '2330', 'shares': 10}),
      ),
      (
        'entry',
        'sellMinus',
        entry('sellMinus', {'type': 'sell', 'holding': '2330', 'shares': -5}),
      ),
      (
        'entry',
        'sharesMax',
        entry('sharesMax', {
          'type': 'buy',
          'holding': '2330',
          'shares': 9223372036854775807,
        }),
      ),
      ('entry', 'huge', entry('huge', {'amount': 9223372036854775807})),
      ('entry', 'minus', entry('minus', {'amount': -5})),
      ('entry', 'parts', entry('parts', {'installments': 99999999999})),
      ('entry', 'nowhere', entry('nowhere', {'type': 'transfer'})),
      (
        'account',
        'due',
        jsonEncode({
          'id': 'due',
          'name': '卡',
          'kind': 'card',
          'opening': 0,
          'dueDay': 40,
        }),
      ),
      (
        'account',
        'close',
        jsonEncode({
          'id': 'close',
          'name': '卡',
          'kind': 'card',
          'opening': 0,
          'closingDay': 99999,
        }),
      ),
      (
        'account',
        'limit',
        jsonEncode({
          'id': 'limit',
          'name': '卡',
          'kind': 'card',
          'opening': 0,
          'limit': -1,
        }),
      ),
      (
        'account',
        'history',
        jsonEncode({
          'id': 'history',
          'name': '卡',
          'kind': 'card',
          'opening': 0,
          'history': [
            {'until': '2026-01-01', 'closingDay': 0, 'dueDay': 10},
          ],
        }),
      ),
      (
        'recurring',
        'day0',
        jsonEncode({
          'id': 'day0',
          'name': '房租',
          'amount': 5,
          'day': 0,
          'account': 'cash',
          'category': '居家',
        }),
      ),
      (
        'recurring',
        'every',
        jsonEncode({
          'id': 'every',
          'name': '房租',
          'amount': 5,
          'day': 5,
          'every': -1,
          'account': 'cash',
          'category': '居家',
        }),
      ),
      ('budget', '餐飲', jsonEncode({'category': '餐飲', 'limit': 100000000000})),
      (
        'trash',
        'gone',
        jsonEncode({
          'on': '2026-10-01',
          'entry': jsonDecode(entry('gone', {'amount': -1})),
        }),
      ),
    ]);
    expect(book.entries.map((e) => e.id), ['buy']);
    expect(book.accounts, isEmpty);
    expect(book.recurring, isEmpty);
    expect(book.budgets, isEmpty);
    expect(book.trash, isEmpty);
    expect(asideOf(book), {
      'entry/sellMinus': 'MissingShares',
      'entry/sharesMax': 'SharesTooLarge',
      'entry/huge': 'AmountTooLarge',
      'entry/minus': 'MissingAmount',
      'entry/parts': 'InstallmentsOutOfRange',
      'entry/nowhere': 'MissingDestination',
      'account/due': 'DueDayOutOfRange',
      'account/close': 'ClosingDayOutOfRange',
      'account/limit': 'NegativeCreditLimit',
      // A card's former schedule is checked as it is read.
      'account/history':
          'FormatException: Unreadable record: '
          'CreditCardException',
      'recurring/day0': 'DayOutOfRange',
      'recurring/every': 'IntervalTooSmall',
      'budget/餐飲': 'AmountTooLarge',
      'trash/gone': 'MissingAmount',
    });
    // The holdings are what the purchase alone leaves.
    expect(book.holdings!.portfolio.holdings.single.shares, 10);
  });

  test('a sale of more than is held still opens, held short (D47)', () {
    final book = decode([
      (
        'entry',
        'b',
        entry('b', {'type': 'buy', 'holding': '2330', 'shares': 10}),
      ),
      (
        'entry',
        's',
        entry('s', {
          'type': 'sell',
          'holding': '2330',
          'shares': 50,
          'date': '2026-09-24',
        }),
      ),
    ]);
    expect(book.aside, isEmpty);
    expect(book.entries.map((e) => e.id), ['b', 's']);
    expect(book.holdings!.tolerated, {'s'});
    expect(book.holdings!.faulty, isEmpty);
  });
}
