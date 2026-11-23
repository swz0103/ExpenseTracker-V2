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

  /// Before every intent: where a stream is posted again from.
  static const Position _start = (date: Day.stored(0), seq: 0);

  /// Keeps [intent], new or in place of the one with its id.
  JournalResult put(LedgerIntent intent) => putAll([intent]);

  /// Keeps every intent of [intents] in one transaction: all, or none.
  JournalResult putAll(Iterable<LedgerIntent> intents) => _write(() {
    var posted = 0;
    var postings = 0;
    final stale = <IntentId>[];
    for (final intent in intents) {
      final r = _put(intent);
      posted += r.posted;
      postings += r.postings;
      stale.addAll(r.stale);
    }
    return (posted: posted, postings: postings, stale: stale);
  });

  /// Takes the intent [id] and its postings away, and posts the later
  /// intents of its streams again.
  JournalResult delete(IntentId id) {
    final old = _store.intent(id);
    if (old == null) return IntentNotFound(id);
    // An intent nobody here can post is read only: what taking it away
    // would do to those after it, nobody here knows.
    if (registry[old.type] == null) return UnknownIntentType(id, old.type);
    return _write(() {
      _store.remove(id);
      return _materialise(streams: {...old.streams}, from: old.position);
    });
  }

  /// Posts every intent of [stream] again: for when something the rules
  /// read that is not an intent changed, such as a card's closing day.
  JournalResult rematerialise(String stream) =>
      _write(() => _materialise(streams: {stream}, from: _start));

  WriteReport _put(LedgerIntent intent) {
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
    final streams = [
      ...spec.streamsOf(intent),
      for (final a in registry.amenders)
        if (intent.amendments.containsKey(a.slot))
          ...?a.streams?.call(
            spec.touchesOf(intent),
            intent.amendments[a.slot],
            accounts,
          ),
    ];
    final row = IntentRow(
      id: intent.id,
      type: intent.type,
      date: intent.date,
      seq: intent.seq,
      streams: streams,
    );
    var from = row.position;
    if (old != null) {
      if (comparePositions(old.position, from) < 0) from = old.position;
      // Its old lines go first, so an intent of its streams posted before
      // it does not read them.
      _store.put(old, const []);
    }
    return _materialise(
      seed: row,
      seedIntent: intent,
      streams: {...streams, ...?old?.streams},
      from: from,
    );
  }

  JournalResult _write(WriteReport Function() body) {
    try {
      return Written(_store.transaction(body));
    } on _Abort catch (abort) {
      return abort.refusal;
    }
  }

  /// Posts [seed] and every intent standing at or after [from] in one of
  /// [streams] (and in the streams of those, and so on), in book order:
  /// each rule sees the postings before it as they now are.
  WriteReport _materialise({
    IntentRow? seed,
    LedgerIntent? seedIntent,
    required Set<String> streams,
    required Position from,
  }) {
    final todo = <IntentId, IntentRow>{?seed?.id: ?seed};
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
    final order = todo.values.toList()
      ..sort((a, b) {
        final byPlace = comparePositions(a.position, b.position);
        return byPlace != 0 ? byPlace : a.id.value.compareTo(b.id.value);
      });
    var written = 0;
    final stale = <IntentId>[];
    for (final row in order) {
      final spec = registry[row.type];
      final intent = identical(row, seed) ? seedIntent : _source(row.id);
      if (spec == null || intent == null) {
        // A follower nobody here can post: its postings stay as written.
        stale.add(row.id);
        continue;
      }
      final context = RuleContext(accounts, _store, row.position);
      final postings = switch (_posted(spec, intent, context)) {
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
      if (line.amount == 0 && line.quantity == 0) continue;
      final account = accounts[line.account];
      if (account == null) {
        throw _Abort(UnknownAccount(row.id, line.account));
      }
      final own = account.currency;
      if (own != null && own != line.currency) {
        throw _Abort(CurrencyMismatch(row.id, account.id, own, line.currency));
      }
      residual[line.currency] = (residual[line.currency] ?? 0) + line.amount;
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
