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
import 'package:expense_tracker/src/app/modules.dart';
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
    entryById: ledger.entries.byId,
    refundsOf: ledger.entries.refundsOf,
  );
  final kept = [
    for (final (i, e) in ledger.entries.all.indexed) (entry: e, seq: i + 1),
  ];
  final byId = {for (final k in kept) k.entry.id: k};
  final store = into ?? MemoryPostingStore();
  // As the app's journal reads: the modules' claims with the valuers.
  final contributions = valuedAsTheApp(
    holdings: ledger.holdings,
    market: ledger.marketData,
  );
  installModules(contributions);
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
    reader: BookReader(store, tree, contributions, homeCurrency),
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

/// The shape of [postingsOf]'s print. Raised when the print itself shows
/// more (r14 F3: each posting's seq, each intent's streams, the account
/// tree), which moves every print with no rule changed: the one other
/// reason `UPDATE_JOURNAL_GOLDEN=1` may keep new prints.
const goldenPrintShape = 2;

/// Every posting of [b], account by account in book order, each intent
/// with the streams it is in, and the account tree: what it posts.
String postingsOf(PostedBook b) {
  final accounts = [...b.reader.accounts.all]
    ..sort((x, y) => x.id.value.compareTo(y.id.value));
  final intents = <IntentId>{};
  return [
    for (final a in accounts) accountLine(a),
    for (final a in accounts)
      for (final p in b.reader.postings(a.id)) ...[
        '$p',
        if (intents.add(p.intent))
          if (b.store.intent(p.intent) case final row?)
            'intent ${row.id.value} ${row.type.value} ${row.date.ymd}/'
                '${row.seq} streams ${row.streams.join(',')}',
      ],
  ].join('\n');
}

/// Whether [now] may be kept over a book's [kept] golden print: the same
/// print, or journalRules or the print's shape raised since it was kept.
bool mayKeepPrint(Map<String, Object?> kept, String now) =>
    kept['print'] == now ||
    kept['journalRules'] != journalRules ||
    kept['printShape'] != goldenPrintShape;

/// [a] as the tree keeps it, every field.
String accountLine(LedgerAccount a) =>
    'account ${a.id.value} ${a.cls.name} ${a.name} ${a.owner.value} '
    'parent ${a.parent?.value} ${a.currency?.value} ${a.commodity} '
    '${a.tag} net ${a.inNetWorth} flow ${a.inFlowReports}';

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
  final now = printOf(postingsOf(b));
  final want = {
    'journalRules': journalRules,
    'printShape': goldenPrintShape,
    'print': now,
  };
  Map<String, Object?> read() =>
      jsonDecode(File(_golden).readAsStringSync()) as Map<String, Object?>;
  final was = (read()['books']! as Map<String, Object?>)[book];
  final kept = was is Map<String, Object?> ? was : const <String, Object?>{};
  if (Platform.environment['UPDATE_JOURNAL_GOLDEN'] != null) {
    // New prints are kept only for a reason: the rules raised, or the
    // print's own shape. A print that moved with neither is a rule
    // changed without raising journalRules (r14 F3), never written over.
    // Each book keeps its own, so books kept one after another each
    // answer for themselves.
    expect(
      mayKeepPrint(kept, now),
      isTrue,
      reason:
          'what $book posts changed but journalRules did not rise: raise '
          'it before keeping new prints',
    );
    // Read again just before writing: another book may have been kept.
    final books = {...(read()['books']! as Map<String, Object?>)};
    books[book] = want;
    const json = JsonEncoder.withIndent('  ');
    File(_golden).writeAsStringSync('${json.convert({'books': books})}\n');
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
    kept['printShape'],
    goldenPrintShape,
    reason:
        'the print shows more: keep the new prints '
        '(UPDATE_JOURNAL_GOLDEN=1)',
  );
  expect(
    kept['print'],
    now,
    reason: 'what $book posts changed without raising journalRules',
  );
}
