import 'package:expense_tracker/src/core/ledger/journal/book_mapping.dart';
import 'package:expense_tracker/src/core/ledger/journal/parity.dart';
import 'package:expense_tracker/src/core/ledger/journal/replay.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/ledger/repositories/holding_repository.dart';
import 'package:kernel/kernel.dart';
import 'package:ledger_postings/model/vocabulary.dart';

/// A ledger's book posted afresh into a memory store, as the app posts
/// it: each entry kept at its place in the ledger.
typedef PostedBook = ({
  ReplayReport report,
  BookReader reader,
  Journal journal,
  MemoryPostingStore store,
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

Future<PostedBook> post(Ledger ledger) async {
  final mapping = BookMapping(
    accounts: ledger.accounts.all,
    categories: ledger.categories.all,
    start: (ledger.holdings as HoldingRepository).start,
  );
  final kept = [
    for (final (i, e) in ledger.entries.all.indexed) (entry: e, seq: i + 1),
  ];
  final byId = {for (final k in kept) k.entry.id: k};
  final store = MemoryPostingStore();
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
    reader: BookReader(store, tree, Contributions(), homeCurrency),
    journal: journal,
    store: store,
  );
}

/// [ledger] posted and compared, everything.
Future<Parity> parityOf(Ledger ledger, {bool everyDay = true}) async {
  final b = await post(ledger);
  return checkParity(
    today: figuresOf(ledger),
    reader: b.reader,
    shapes: b.report.shapes,
    unposted: b.report.unposted,
    everyDay: everyDay,
  );
}
