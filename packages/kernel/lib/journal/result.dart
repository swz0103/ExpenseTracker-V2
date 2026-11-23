import '../model/ids.dart';

/// What a write did: how many intents were posted (more than one when
/// later intents of a stream followed), how many postings now stand for
/// them, and [stale]: intents of a touched stream left as they were,
/// because nobody here can post their kind any more.
typedef WriteReport = ({int posted, int postings, List<IntentId> stale});

/// What the journal answers a write: written, or refused with nothing
/// changed. Sealed, so a caller's switch covers every case.
sealed class JournalResult {
  const JournalResult();
}

final class Written extends JournalResult {
  const Written(this.report);
  final WriteReport report;
}

/// A write the journal would not keep; nothing was changed.
sealed class JournalRefusal extends JournalResult {
  const JournalRefusal(this.intent);

  /// The intent refused: the one written, or one after it in a stream.
  final IntentId intent;
}

/// The lines of [intent] do not come to zero in [currency].
final class Unbalanced extends JournalRefusal {
  const Unbalanced(super.intent, this.currency, this.residual);
  final CurrencyCode currency;
  final int residual;
}

/// A line of [intent] names [account], which the book has not.
final class UnknownAccount extends JournalRefusal {
  const UnknownAccount(super.intent, this.account);
  final AccountId account;
}

/// A line of [intent] puts [got] on [account], kept in [expected].
final class CurrencyMismatch extends JournalRefusal {
  const CurrencyMismatch(super.intent, this.account, this.expected, this.got);
  final AccountId account;
  final CurrencyCode expected;
  final CurrencyCode got;
}

/// Nobody here posts intents of [type]: such an intent is read only.
final class UnknownIntentType extends JournalRefusal {
  const UnknownIntentType(super.intent, this.type);
  final IntentType type;
}

/// No intent of that id is kept.
final class IntentNotFound extends JournalRefusal {
  const IntentNotFound(super.intent);
}

/// A posting rule or an amender would not post [intent]: [code] is its
/// own stable word, [detail] what it names (a stock, a slot).
final class RuleRejected extends JournalRefusal {
  const RuleRejected(super.intent, this.code, [this.detail = '']);
  final String code;
  final String detail;
}

/// [intent] carries a value under [slot] that no amender here reads, or
/// its kind takes none: posting it would drop the value.
final class UnknownAmendment extends JournalRefusal {
  const UnknownAmendment(super.intent, this.slot);
  final String slot;
}
