import '../model/accounts.dart';
import '../model/day.dart';
import '../model/ids.dart';
import '../model/posting.dart';
import 'store.dart';

/// What the person meant: one record as they kept it, such as a
/// spending. The journal reads its [id], [date], [seq], [type] and
/// [amendments], and hands the rest to the rule of its kind. Named so as
/// not to be taken for Flutter's `Intent`.
abstract base class LedgerIntent {
  const LedgerIntent({
    required this.id,
    required this.date,
    required this.seq,
    this.amendments = const {},
  });

  final IntentId id;
  final Day date;

  /// The order it was first kept in, which an edit keeps: of two intents
  /// of a day, the one kept first stands first.
  final int seq;

  /// Values kept with the intent for other owners' [Amender]s, by slot:
  /// a foreign amount's worth at home, how many instalments.
  final Map<String, Object?> amendments;

  IntentType get type;

  Position get position => (date: date, seq: seq);
}

/// What a rule may look at besides its intent: the accounts, and the
/// postings standing before the intent. Nothing after it, and no
/// setting: a rule that read one would change history when it changed.
final class RuleContext {
  RuleContext(this.accounts, this._store, this.position);

  final AccountTree accounts;
  final PostingStore _store;
  final Position position;

  /// The postings on [account] standing before this intent, in book
  /// order.
  List<Posting> before(AccountId account) =>
      _store.postingsOf(account, before: position);
}

/// What a rule answers: the lines, or its own stable word for why not.
sealed class Posted {
  const Posted();
}

final class Lines extends Posted {
  const Lines(this.lines);
  final List<Line> lines;
}

final class Refused extends Posted {
  const Refused(this.code, [this.detail = '']);
  final String code;
  final String detail;
}

/// How one kind of intent becomes lines.
abstract interface class PostingRule<I extends LedgerIntent> {
  /// The ordered streams the intent's lines read or feed, such as one
  /// stock's lots: writing it posts every later intent of them again.
  /// Empty for an intent whose lines follow from itself alone.
  Iterable<String> streams(I intent);

  /// The lines of [intent], or why it cannot be kept. Pure: the intent
  /// and [context], nothing else.
  Posted post(I intent, RuleContext context);
}

/// What an owner registers for one kind of intent.
final class IntentSpec<I extends LedgerIntent> {
  const IntentSpec({
    required this.type,
    required this.owner,
    required this.rule,
    this.amendable = false,
    this.touches,
  });

  final IntentType type;
  final OwnerId owner;
  final PostingRule<I> rule;

  /// Whether other owners' [Amender]s may rewrite this kind's lines.
  final bool amendable;

  /// The money accounts an intent names, for an amender whose stream
  /// depends on them (a card's instalments).
  final Iterable<AccountId> Function(I intent)? touches;

  // The registry holds specs of every kind; the one cast is here.
  Iterable<String> streamsOf(LedgerIntent i) => rule.streams(i as I);
  Posted linesOf(LedgerIntent i, RuleContext c) => rule.post(i as I, c);
  Iterable<AccountId> touchesOf(LedgerIntent i) =>
      touches?.call(i as I) ?? const [];
}

/// What an amender is given: the intent, the value kept under its slot
/// (null when none), the lines as they stand and the rule's context.
typedef Amendment = ({
  LedgerIntent intent,
  Object? value,
  List<Line> lines,
  RuleContext context,
});

/// One owner's rewrite of the lines of other owners' amendable intents,
/// driven by the value kept under [slot]. It sees every amendable
/// intent, value or none, so it can refuse lines that need its value.
final class Amender {
  const Amender({
    required this.slot,
    required this.owner,
    required this.order,
    required this.amend,
    this.streams,
  });

  final String slot;
  final OwnerId owner;

  /// Amenders run in this order, lowest first.
  final int order;
  final Posted Function(Amendment amendment) amend;

  /// The streams an intent amended with [value] joins, from the money
  /// accounts it [touched].
  final Iterable<String> Function(
    Iterable<AccountId> touched,
    Object? value,
    AccountTree accounts,
  )?
  streams;
}

/// Every kind of intent and every amender the app posts with.
final class IntentRegistry {
  final _specs = <IntentType, IntentSpec>{};
  final _amenders = <Amender>[];

  void register<I extends LedgerIntent>(IntentSpec<I> spec) {
    if (_specs.containsKey(spec.type)) {
      throw StateError('intent type registered twice: ${spec.type.value}');
    }
    _specs[spec.type] = spec;
  }

  void amend(Amender amender) {
    if (amenderOf(amender.slot) != null) {
      throw StateError('amendment slot registered twice: ${amender.slot}');
    }
    _amenders
      ..add(amender)
      ..sort((a, b) => a.order.compareTo(b.order));
  }

  /// The amenders, in the order they run.
  List<Amender> get amenders => List.unmodifiable(_amenders);

  Amender? amenderOf(String slot) {
    for (final a in _amenders) {
      if (a.slot == slot) return a;
    }
    return null;
  }

  IntentSpec? operator [](IntentType type) => _specs[type];
  Iterable<IntentType> get types => _specs.keys;
}
