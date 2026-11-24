import 'dart:convert';
import 'dart:io';

import 'package:expense_tracker/src/core/ledger/journal/book_mapping.dart';
import 'package:expense_tracker/src/core/ledger/journal/parity.dart';
import 'package:expense_tracker/src/core/ledger/journal/replay.dart';
import 'package:expense_tracker/src/core/ledger/journal/valuation.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/ledger/repositories/holding_repository.dart';
import 'package:expense_tracker/src/core/ledger/persistence/journal_keeper.dart'
    show journalRules;
import 'package:flutter_test/flutter_test.dart';
import 'package:kernel/kernel.dart';
import 'package:ledger_postings/model/vocabulary.dart';

/// A ledger's book posted afresh into a store (a memory store unless one
/// is given), as the app posts it: each entry kept at its place in the
/// ledger.
typedef PostedBook = ({
  ReplayReport report,
  BookReader reader,
  Journal journal,
  PostingStore store,
});

/// What [l] shows today, for [checkParity].
TodaysFigures figuresOf(Ledger l) => (
  day: l.today,
  entries: l.entries,
  accounts: l.accounts,
  holdings: l.holdings,
  balances: l.balanceService,
  reports: l.reportService,
  statements: l.statementService,
);

Future<PostedBook> post(Ledger ledger, {PostingStore? into}) async {
  final mapping = BookMapping(
    accounts: ledger.accounts.all,
    categories: ledger.categories.all,
    start: (ledger.holdings as HoldingRepository).start,
  );
  final kept = [
    for (final (i, e) in ledger.entries.all.indexed) (entry: e, seq: i + 1),
  ];
  final byId = {for (final k in kept) k.entry.id: k};
  final store = into ?? MemoryPostingStore();
  final tree = AccountTree();
  final journal = Journal(
    registry: registryFor(() => mapping),
    accounts: tree,
    store: store,
    source: (id) => switch (byId[id.value]) {
      final k? => mapping.map(k.entry, k.seq).intent,
      null => null,
    },
  );
  final report = await replayBook(
    mapping: mapping,
    journal: journal,
    store: store,
    entries: kept,
    chunk: 50,
  );
  return (
    report: report,
    reader: BookReader(
      store,
      tree,
      valuedAsTheApp(holdings: ledger.holdings, market: ledger.marketData),
      homeCurrency,
    ),
    journal: journal,
    store: store,
  );
}

/// [ledger] posted (into [into], or a memory store) and compared,
/// everything.
Future<Parity> parityOf(
  Ledger ledger, {
  bool everyDay = true,
  PostingStore? into,
}) async {
  final b = await post(ledger, into: into);
  return checkParity(
    today: figuresOf(ledger),
    reader: b.reader,
    shapes: b.report.shapes,
    unposted: b.report.unposted,
    everyDay: everyDay,
  );
}

/// Where the postings each fixture book gives are kept, with the
/// [journalRules] they were posted by.
const _golden = 'test/fixtures/journal/postings_golden.json';

/// Every posting of [b], account by account in book order: what it posts.
String postingsOf(PostedBook b) {
  final accounts = [...b.reader.accounts.all]
    ..sort((x, y) => x.id.value.compareTo(y.id.value));
  return [
    for (final a in accounts)
      for (final p in b.reader.postings(a.id)) '$p',
  ].join('\n');
}

/// A short print of [text] (64-bit FNV-1a).
String printOf(String text) {
  var hash = 0xcbf29ce484222325;
  for (final byte in utf8.encode(text)) {
    hash = (hash ^ byte) * 0x100000001b3;
  }
  return BigInt.from(hash).toUnsigned(64).toRadixString(16).padLeft(16, '0');
}

/// That [book], posted as [b], gives the postings it gave when the golden
/// prints were kept: a change of what a record posts fails here unless
/// [journalRules] was raised with it (and the prints kept again, with
/// `UPDATE_JOURNAL_GOLDEN=1`), so no book keeps postings an older rule
/// made without being posted afresh.
void expectGoldenPostings(String book, PostedBook b) {
  final file = File(_golden);
  final kept = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  final books = {...(kept['books']! as Map<String, Object?>)};
  final now = printOf(postingsOf(b));
  if (Platform.environment['UPDATE_JOURNAL_GOLDEN'] != null) {
    books[book] = now;
    const json = JsonEncoder.withIndent('  ');
    file.writeAsStringSync(
      '${json.convert({'journalRules': journalRules, 'books': books})}\n',
    );
    return;
  }
  expect(
    kept['journalRules'],
    journalRules,
    reason:
        'journalRules was raised: keep the new prints '
        '(UPDATE_JOURNAL_GOLDEN=1)',
  );
  expect(
    books[book],
    now,
    reason: 'what $book posts changed without raising journalRules',
  );
}
