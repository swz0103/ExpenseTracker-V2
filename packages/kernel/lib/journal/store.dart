import '../model/accounts.dart';
import '../model/day.dart';
import '../model/ids.dart';
import '../model/posting.dart';

/// An intent as the journal keeps it: where it stands and which streams
/// it is in. Its body is kept with the records, not here.
final class IntentRow {
  const IntentRow({
    required this.id,
    required this.type,
    required this.date,
    required this.seq,
    this.streams = const [],
  });

  final IntentId id;
  final IntentType type;
  final Day date;
  final int seq;
  final List<String> streams;

  Position get position => (date: date, seq: seq);
}

/// What postings add up to: money in minor units, and quantity.
typedef AccountSum = ({int amount, BigInt quantity});

/// Before every intent of a book, its openings included: where a whole
/// stream is read from.
const Position startOfBook = (date: Day.beforeAll, seq: 0);

/// Nothing posted.
final AccountSum noSum = (amount: 0, quantity: BigInt.zero);

/// Whether [sum] is nothing.
bool isNoSum(AccountSum sum) => sum.amount == 0 && sum.quantity == BigInt.zero;

/// A sum by account and currency.
typedef AccountSums = Map<(AccountId, CurrencyCode), AccountSum>;

/// What the postings kept were posted from: by which version of the
/// rules, and up to which change of the records. A mark that is not the
/// rules' and the records' own says the postings are to be posted again.
typedef JournalMark = ({int rules, int revision});

/// Where the journal keeps intents' places, their postings, the sum of
/// each month and the account tree. All of it can be thrown away and
/// posted again from the records ([clear]).
abstract interface class PostingStore {
  /// The mark kept with the postings; null before any were posted.
  JournalMark? get mark;

  /// Keeps [mark], in the transaction under way when there is one.
  void keepMark(JournalMark mark);

  /// Runs [body]; whatever it wrote is undone when it throws.
  T transaction<T>(T Function() body);

  IntentRow? intent(IntentId id);

  /// Keeps [row] with exactly [postings], in place of what it had, and
  /// the months' sums with them.
  void put(IntentRow row, List<Posting> postings);

  /// Forgets the intent [id] and its postings.
  void remove(IntentId id);

  /// The intents of [stream] standing at or after [from], in book order.
  List<IntentRow> inStream(String stream, {required Position from});

  List<Posting> postingsOfIntent(IntentId id);

  /// The postings on [account] in book order (by day, then the order
  /// their intents were kept, then line); with [before], those standing
  /// before it.
  List<Posting> postingsOf(AccountId account, {Position? before});

  /// What the postings on [account] add up to on each day they are dated,
  /// in day order: the steps of its running balance, without reading each
  /// posting.
  List<(Day, int)> daySums(AccountId account);

  /// What the postings dated from [from] to [until] add up to, each end
  /// counted, by account and currency: one aggregate behind every
  /// balance and report.
  AccountSums sums({Day? from, Day? until});

  /// What the postings on [account] up to [until] add up to by sub key
  /// and currency: a holding's lots, gains by stock.
  Map<(String, CurrencyCode), AccountSum> subSums(
    AccountId account, {
    Day? until,
  });

  /// The account tree kept with the postings.
  List<LedgerAccount> accounts();

  /// Keeps [accounts] as the whole tree, in place of the one before.
  void keepAccounts(Iterable<LedgerAccount> accounts);

  /// Forgets every intent, posting and monthly sum (not the accounts),
  /// and the mark, before everything is posted again: a journal cleared
  /// and not yet posted whole is never taken for the records' own.
  void clear();

  int get intentCount;
  int get postingCount;
}

/// [a] and [b] added.
AccountSum addSums(AccountSum a, AccountSum b) =>
    (amount: a.amount + b.amount, quantity: a.quantity + b.quantity);

/// What [postings], in book order, add up to on each day, in day order.
List<(Day, int)> sumByDay(List<Posting> postings) {
  final days = <(Day, int)>[];
  for (final p in postings) {
    if (days.isNotEmpty && days.last.$1 == p.date) {
      days.last = (p.date, days.last.$2 + p.amount);
    } else {
      days.add((p.date, p.amount));
    }
  }
  return days;
}
