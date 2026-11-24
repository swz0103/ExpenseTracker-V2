import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:expense_tracker/src/core/ledger/persistence/book_opening.dart';
import 'package:expense_tracker/src/core/ledger/persistence/journal_keeper.dart';
import 'package:expense_tracker/src/core/ledger/persistence/journal_rebuild.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storage/storage.dart';

/// A helper worker that cannot be started, as a phone short of memory
/// refuses one.
Future<DecodedRecords> _refused(List<StoredRow> rows) =>
    throw IsolateSpawnException('no memory');

/// A helper worker that fails once started.
Future<DecodedRecords> _failing(List<StoredRow> rows) =>
    Future.error(StateError('the worker failed'));

/// Review 24: the split opening of a large book (`openingWork`), its
/// threshold lowered so ten entries are split, reads the book exactly as
/// it is read in one piece ([decodeBook]), the journal posted from it.
void main() {
  final today = DateTime.utc(2026, 10, 4);
  final trashFrom = DateTime.utc(2026, 9, 4);

  late Directory dir;
  late EncryptedDatabase store;

  String entry(String id, [Map<String, Object?> extra = const {}]) =>
      jsonEncode({
        'id': id,
        'date': '2026-09-04',
        'type': 'expense',
        'amount': 5,
        'account': 'cash',
        'category': '飲食日常',
        ...extra,
      });

  setUp(() {
    dir = Directory.systemTemp.createTempSync('opening-split-');
    store = EncryptedDatabase.open(
      File('${dir.path}/l.db'),
      StorageKey.random(),
    );
    store.write((w) {
      w.put(
        'account',
        'cash',
        jsonEncode({'id': 'cash', 'name': '現金', 'kind': 'cash', 'opening': 0}),
      );
      w.put(
        'category',
        'food',
        jsonEncode({'id': 'food', 'name': '飲食日常', 'icon': 'food', 'color': 1}),
      );
      // Ten entry rows: the first half (rows e0–e4) with one that is not
      // JSON and one a later version wrote, the last half (e5–e9) the
      // same, so each half sets rows aside.
      for (var i = 0; i < 10; i++) {
        w.put('entry', 'e$i', switch (i) {
          1 || 6 => 'not json',
          3 || 8 => '{"_v":99,${entry('e$i').substring(1)}',
          _ => entry('e$i', {
            'note': i.isEven ? '午餐' : '晚餐',
            'tags': ['家用'],
          }),
        });
      }
      w.put(
        'trash',
        't',
        jsonEncode({'on': '2026-09-20', 'entry': jsonDecode(entry('t'))}),
      );
    });
  });

  tearDown(() {
    store.close();
    dir.deleteSync(recursive: true);
  });

  /// The book opened as the app opens it with the journal kept: sent for
  /// the screens as soon as it is read, then posted.
  Future<(ReadBook, OpenedBook)> open({
    DecodeApart decodeApart = decodedApart,
  }) async {
    final books = ReceivePort();
    try {
      final work = store.workApart(
        openingWork(
          books: books.sendPort,
          today: today,
          trashFrom: trashFrom,
          rules: journalRules,
          split: true,
          splitFrom: 4,
          decodeApart: decodeApart,
        ),
      );
      final read = await books.first as ReadBook;
      return (read, await work);
    } finally {
      books.close();
    }
  }

  void expectAsWhole(DecodedBook book) {
    final whole = decodeBook(
      shelvesOf(store.rows()),
      trashFrom: trashFrom,
      today: today,
    );
    // e0, e2, e4, e5, e7, e9 read; at rows 3, 5, 7, 8, 10, 12 (the
    // account row 1, the category row 2, the entries from row 3 on).
    expect(book.entries.map((e) => e.id), ['e0', 'e2', 'e4', 'e5', 'e7', 'e9']);
    expect(book.entryPlaces, [3, 5, 7, 8, 10, 12]);
    expect(whole.entries.map((e) => e.id), book.entries.map((e) => e.id));
    expect(whole.entryPlaces, book.entryPlaces);
    // Set aside in row order, both halves.
    const aside = ['entry/e1', 'entry/e3', 'entry/e6', 'entry/e8'];
    expect(book.aside.map((r) => r.key), aside);
    expect(
      [for (final r in book.aside) (r.key, r.reason, r.detail)],
      [for (final r in whole.aside) (r.key, r.reason, r.detail)],
    );
    expect(book.namesOf, whole.namesOf);
    expect(book.namesOf['entry/e9'], isNotNull);
    expect(book.trash.map((t) => t.entry.id), ['t']);
    expect(book.trash.single.order, whole.trash.single.order);
    // Even rows 午餐, odd 晚餐: e0, e2, e4, then e5, e7, e9.
    const notes = ['午餐', '午餐', '午餐', '晚餐', '晚餐', '晚餐'];
    expect(book.entries.map((e) => e.note), notes);
    expect(whole.entries.map((e) => e.note), notes);
    expect(book.entries.expand((e) => e.tags), List.filled(6, '家用'));
  }

  void expectPosted(OpenedBook opened) {
    expect(opened.book, isNull, reason: 'sent before it was posted');
    expect(opened.posted, isNotNull);
    expect(store.journal.mark, (rules: journalRules, revision: store.revision));
    // One intent for each of the six entries read.
    expect(store.journal.intentCount, 6);
  }

  test('a book split in two reads as the whole book, and is posted', () async {
    final (read, opened) = await open();
    expect(read.worked.split, isTrue);
    expect(opened.worked.split, isTrue);
    expect(read.worked.helperFault, isNull);
    expectAsWhole(read.book);
    expectPosted(opened);
  });

  test('a helper worker that cannot start leaves its half decoded on the '
      'opening worker', () async {
    final (read, opened) = await open(decodeApart: _refused);
    expect(read.worked.split, isFalse);
    expect(read.worked.helperFault, startsWith('IsolateSpawnException: '));
    expectAsWhole(read.book);
    expectPosted(opened);
  });

  test('a helper worker that fails leaves its half decoded on the opening '
      'worker', () async {
    final (read, opened) = await open(decodeApart: _failing);
    expect(read.worked.split, isFalse);
    expect(read.worked.helperFault, startsWith('StateError: '));
    expectAsWhole(read.book);
    expectPosted(opened);
  });

  test('below the threshold, or without split, nothing is split', () async {
    final books = ReceivePort();
    addTearDown(books.close);
    final opened = await store.workApart(
      openingWork(
        books: books.sendPort,
        today: today,
        trashFrom: trashFrom,
        rules: null,
        split: true,
        splitFrom: 11,
      ),
    );
    expect(opened.worked.split, isFalse);
    expectAsWhole(opened.book!);
    final unsplit = await store.workApart(
      openingWork(
        books: books.sendPort,
        today: today,
        trashFrom: trashFrom,
        rules: null,
        splitFrom: 4,
      ),
    );
    expect(unsplit.worked.split, isFalse);
  });
}
