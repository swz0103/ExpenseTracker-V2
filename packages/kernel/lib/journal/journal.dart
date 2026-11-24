import '../model/accounts.dart';
import '../model/day.dart';
import '../model/ids.dart';
import '../model/posting.dart';
import 'intent.dart';
import 'result.dart';
import 'store.dart';

/// Where the journal finds an intent it must post again, a later one of
/// a stream it wrote into: the records keep the intents, the journal
/// only their places. Null when there is none.
typedef IntentSource = LedgerIntent? Function(IntentId id);

/// The one write path of the postings: an intent in, its balanced lines
/// kept in one transaction with those of every later intent of its
/// streams; or nothing changed and why not.
final class Journal {
  Journal({
    required this.registry,
    required this.accounts,
    required this._store,
    required this._source,
  });

  final IntentRegistry registry;
  final AccountTree accounts;
  final PostingStore _store;
  final IntentSource _source;

  /// Keeps [intent], new or in place of the one with its id.
  JournalResult put(LedgerIntent intent) => putAll([intent]);

  /// Keeps every intent of [intents] in one transaction: all, or none.
  /// They are posted together, with every later intent of their streams,
  /// in book order (by place, then id), whatever order they are given in:
  /// a sale listed before its purchase reads the purchase. [also] writes
  /// what goes with them (a mark, accounts) in the same transaction, once
  /// they are posted, and only when every follower could be posted again
  /// ([WriteReport.stale] empty): a journal left with stale postings is
  /// never marked as up to date.
  ///
  /// The followers come from the [IntentSource]; the intents of the batch
  /// from the batch itself, so the source need not hold them yet.
  JournalResult putAll(
    Iterable<LedgerIntent> intents, {
    void Function()? also,
  }) => _write(also, () {
    final seeds = <IntentId, (IntentRow, LedgerIntent)>{};
    final streams = <String>{};
    Position? from;
    void earliest(Position p) {
      if (from == null || comparePositions(p, from!) < 0) from = p;
    }

    for (final intent in intents) {
      final spec = registry[intent.type];
      if (spec == null) {
        throw _Abort(UnknownIntentType(intent.id, intent.type));
      }
      final old = _store.intent(intent.id);
      if (old != null && registry[old.type] == null) {
        throw _Abort(UnknownIntentType(intent.id, old.type));
      }
      for (final slot in intent.amendments.keys) {
        if (!spec.amendable || registry.amenderOf(slot) == null) {
          throw _Abort(UnknownAmendment(intent.id, slot));
        }
      }
      final row = IntentRow(
        id: intent.id,
        type: intent.type,
        date: intent.date,
        seq: intent.seq,
        streams: _streamsOf(spec, intent),
      );
      seeds[intent.id] = (row, intent);
      streams.addAll(row.streams);
      earliest(row.position);
      if (old != null) {
        streams.addAll(old.streams);
        earliest(old.position);
        // Its old lines go first, so no intent posted before it reads
        // them.
        _store.put(old, const []);
      }
    }
    if (seeds.isEmpty) {
      return (posted: 0, postings: 0, stale: const <IntentId>[]);
    }
    return _materialise(seeds: seeds, streams: streams, from: from!);
  });

  /// Takes the intent [id] and its postings away, and posts the later
  /// intents of its streams again; [also] as in [putAll].
  JournalResult delete(IntentId id, {void Function()? also}) {
    final old = _store.intent(id);
    if (old == null) return IntentNotFound(id);
    // An intent nobody here can post is read only: what taking it away
    // would do to those after it, nobody here knows.
    if (registry[old.type] == null) return UnknownIntentType(id, old.type);
    return _write(also, () {
      _store.remove(id);
      return _materialise(
        seeds: const {},
        streams: {...old.streams},
        from: old.position,
      );
    });
  }

  /// Posts every intent of [stream] again: for when something the rules
  /// read that is not an intent changed, such as a card's closing day;
  /// [also] as in [putAll].
  JournalResult rematerialise(String stream, {void Function()? also}) => _write(
    also,
    () => _materialise(seeds: const {}, streams: {stream}, from: startOfBook),
  );

  /// The streams [intent] is in: its rule's, and those its amendments
  /// add. An intent in none is posted from itself alone, whatever was
  /// posted before it: a whole book can post those in any order, apart.
  /// Empty for a kind nobody here posts.
  List<String> streamsOf(LedgerIntent intent) =>
      switch (registry[intent.type]) {
        final spec? => _streamsOf(spec, intent),
        null => const [],
      };

  List<String> _streamsOf(IntentSpec spec, LedgerIntent intent) => [
    ...spec.streamsOf(intent),
    for (final a in registry.amenders)
      if (intent.amendments.containsKey(a.slot))
        ...?a.streams?.call(
          spec.touchesOf(intent),
          intent.amendments[a.slot],
          accounts,
        ),
  ];

  JournalResult _write(void Function()? also, WriteReport Function() body) {
    try {
      return Written(
        _store.transaction(() {
          final report = body();
          if (report.stale.isEmpty) also?.call();
          return report;
        }),
      );
    } on _Abort catch (abort) {
      return abort.refusal;
    }
  }

  /// Posts [seeds] and every intent standing at or after [from] in one of
  /// [streams] (and in the streams of those, and so on), in book order:
  /// each rule sees the postings before it as they now are.
  WriteReport _materialise({
    required Map<IntentId, (IntentRow, LedgerIntent)> seeds,
    required Set<String> streams,
    required Position from,
  }) {
    final todo = <IntentId, IntentRow>{
      for (final MapEntry(:key, value: (row, _)) in seeds.entries) key: row,
    };
    final seen = <String>{};
    final queue = [...streams];
    while (queue.isNotEmpty) {
      final stream = queue.removeLast();
      if (!seen.add(stream)) continue;
      for (final row in _store.inStream(stream, from: from)) {
        if (todo.containsKey(row.id)) continue;
        todo[row.id] = row;
        queue.addAll(row.streams);
      }
    }
    // Most writes post their own intent alone: nothing to order.
    final order = todo.length == 1
        ? [todo.values.single]
        : (todo.values.toList()..sort((a, b) {
            final byPlace = comparePositions(a.position, b.position);
            return byPlace != 0 ? byPlace : a.id.value.compareTo(b.id.value);
          }));
    var written = 0;
    final stale = <IntentId>[];
    for (final row in order) {
      final spec = registry[row.type];
      final intent = seeds[row.id]?.$2 ?? _source(row.id);
      if (spec == null || intent == null) {
        // A follower nobody here can post: its postings stay as written.
        stale.add(row.id);
        continue;
      }
      final context = RuleContext(accounts, _store, row.position);
      final posted = _posted(spec, intent, context);
      final postings = switch (posted) {
        Refused(:final code, :final detail) => throw _Abort(
          RuleRejected(row.id, code, detail),
        ),
        Lines(:final lines) => _check(row, lines),
      };
      _store.put(row, postings);
      written += postings.length;
    }
    return (
      posted: order.length - stale.length,
      postings: written,
      stale: stale,
    );
  }

  /// The rule's lines, then each amender's rewrite, in order.
  Posted _posted(IntentSpec spec, LedgerIntent intent, RuleContext context) {
    var posted = spec.linesOf(intent, context);
    if (!spec.amendable) return posted;
    for (final amender in registry.amenders) {
      if (posted is! Lines) break;
      posted = amender.amend((
        intent: intent,
        value: intent.amendments[amender.slot],
        lines: posted.lines,
        context: context,
      ));
    }
    return posted;
  }

  /// [lines] as postings of [row]; or an abort: every account known, in
  /// its own currency, and the lines coming to zero in each currency.
  List<Posting> _check(IntentRow row, List<Line> lines) {
    final residual = <CurrencyCode, int>{};
    final postings = <Posting>[];
    for (final line in lines) {
      if (line.amount == 0 && line.quantity == BigInt.zero) continue;
      final account = accounts[line.account];
      if (account == null) {
        throw _Abort(UnknownAccount(row.id, line.account));
      }
      final own = account.currency;
      if (own != null && own != line.currency) {
        throw _Abort(CurrencyMismatch(row.id, account.id, own, line.currency));
      }
      final was = residual[line.currency] ?? 0;
      final sum = was + line.amount;
      // A sum past what 64 bits hold wraps: such lines never balance.
      if ((was ^ sum) & (line.amount ^ sum) < 0) {
        throw _Abort(Unbalanced(row.id, line.currency, sum));
      }
      residual[line.currency] = sum;
      postings.add(
        Posting(
          intent: row.id,
          line: postings.length,
          account: line.account,
          amount: line.amount,
          currency: line.currency,
          date: line.date ?? row.date,
          seq: row.seq,
          quantity: line.quantity,
          sub: line.sub,
        ),
      );
    }
    for (final MapEntry(:key, :value) in residual.entries) {
      if (value != 0) throw _Abort(Unbalanced(row.id, key, value));
    }
    return postings;
  }
}

/// Unwinds the transaction of a refused write; never leaves the journal.
final class _Abort implements Exception {
  const _Abort(this.refusal);
  final JournalRefusal refusal;
}
