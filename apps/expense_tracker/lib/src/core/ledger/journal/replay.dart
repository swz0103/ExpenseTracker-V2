import 'package:kernel/kernel.dart';
import 'package:ledger_postings/model/intents.dart';
import 'package:ledger_postings/model/vocabulary.dart';
import 'package:ledger_postings/rules/registry.dart';

import '../models/models.dart';
import 'book_mapping.dart';
import 'old_shapes.dart';

/// An entry with the place it was first kept in: the order of a day's
/// records, which an edit keeps.
typedef KeptEntry = ({Entry entry, int seq});

/// What posting a book did: how many intents it posted, the old shapes
/// it met, by how many records, and the records the journal would not
/// post, each with why.
final class ReplayReport {
  ReplayReport();

  var intents = 0;

  final shapes = <OldShape, int>{};
  final unposted = <JournalRefusal>[];

  /// Notes [found] once more each.
  void count(Iterable<OldShape> found) {
    _count(found);
  }

  /// Adds what [other] found, of another part of the same book.
  void add(ReplayReport other) {
    intents += other.intents;
    other.shapes.forEach(
      (shape, n) => shapes[shape] = (shapes[shape] ?? 0) + n,
    );
    unposted.addAll(other.unposted);
  }

  void _count(Iterable<OldShape> found) {
    for (final shape in found) {
      shapes[shape] = (shapes[shape] ?? 0) + 1;
    }
  }
}

/// The rules of today's records, reading each account's billing days
/// from [mapping] as it is when they run: a mapping taken up later (an
/// account's days changed) is the one read.
IntentRegistry registryFor(BookMapping Function() mapping) =>
    todaysIntents(scheduleOf: (account) => mapping().scheduleOf(account));

/// Posts the whole book afresh: every intent and posting of [store]
/// thrown away, the tree of [mapping] kept, then the openings and every
/// entry of [entries] in book order, [chunk] at a time, each chunk one
/// transaction, with [pause] between chunks so a large book does not
/// hold the screen still.
///
/// A sale or reduction an older version let take more shares than were
/// held is posted as its holdings read it today, out of the holdings
/// ([OldShape.oversoldTrade]); any other record refused is left out and
/// reported.
Future<ReplayReport> replayBook({
  required BookMapping mapping,
  required Journal journal,
  required PostingStore store,
  required Iterable<KeptEntry> entries,
  required int chunk,
  Future<void> Function()? pause,
}) async {
  final report = ReplayReport();
  final tree = mapping.tree;
  for (final account in tree) {
    journal.accounts.put(account);
  }
  store.transaction(() {
    store.clear();
    store.keepAccounts(journal.accounts.all);
  });
  postIntents(journal, mapping.openings, report, const {});
  final ordered = [...entries]
    ..sort((a, b) {
      final byDay = a.entry.date.compareTo(b.entry.date);
      return byDay != 0 ? byDay : a.seq.compareTo(b.seq);
    });
  for (var start = 0; start < ordered.length; start += chunk) {
    final intents = <LedgerIntent>[];
    final records = <IntentId, (Entry, Set<OldShape>)>{};
    final end = start + chunk < ordered.length ? start + chunk : ordered.length;
    for (final (:entry, :seq) in ordered.sublist(start, end)) {
      final mapped = mapping.map(entry, seq);
      for (final account in mapped.accounts) {
        journal.accounts.put(account);
      }
      intents.add(mapped.intent);
      records[mapped.intent.id] = (entry, mapped.shapes);
    }
    postIntents(journal, intents, report, records, mapping: mapping);
    if (pause != null && end < ordered.length) await pause();
  }
  store.transaction(() => store.keepAccounts(journal.accounts.all));
  return report;
}

/// Posts [intents] in one transaction; a refused one is replaced by its
/// reading today (an oversold trade) or left out, and the rest posted
/// again. [records] holds each intent's entry and old shapes; [mapping]
/// gives an oversold trade's reading.
void postIntents(
  Journal journal,
  List<LedgerIntent> intents,
  ReplayReport report,
  Map<IntentId, (Entry, Set<OldShape>)> records, {
  BookMapping? mapping,
}) {
  final todo = [...intents];
  while (todo.isNotEmpty) {
    final result = journal.putAll(todo);
    if (result is Written) {
      report.intents += todo.length;
      for (final intent in todo) {
        report.count(records[intent.id]?.$2 ?? const {});
      }
      break;
    }
    final refusal = result as JournalRefusal;
    final at = todo.indexWhere((i) => i.id == refusal.intent);
    if (at < 0) throw StateError('refused outside the batch: $refusal');
    final was = todo[at];
    final record = records[was.id];
    if (mapping != null &&
        record != null &&
        refusal is RuleRejected &&
        refusal.code == Refusals.oversold &&
        was is! OutOfHoldings) {
      todo[at] = mapping.outOfHoldings(record.$1, was);
      record.$2.add(OldShape.oversoldTrade);
      continue;
    }
    report.unposted.add(refusal);
    todo.removeAt(at);
  }
}
