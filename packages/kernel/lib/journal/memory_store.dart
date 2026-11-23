import '../model/accounts.dart';
import '../model/day.dart';
import '../model/ids.dart';
import '../model/posting.dart';
import 'store.dart';

/// A [PostingStore] in memory: for tests, and for posting a whole book
/// before it is written out. It keeps the months' sums as the file store
/// does, and answers [sums] from them the same way.
final class MemoryPostingStore implements PostingStore {
  final _rows = <IntentId, IntentRow>{};
  final _postings = <IntentId, List<Posting>>{};
  final _streams = <String, Set<IntentId>>{};
  final _touching = <AccountId, Set<IntentId>>{};
  final _byMonth = <int, Set<IntentId>>{};
  final _months = <int, AccountSums>{};
  var _accounts = <LedgerAccount>[];
  var _count = 0;
  List<void Function()>? _undo;

  @override
  T transaction<T>(T Function() body) {
    if (_undo != null) throw StateError('nested transaction');
    final undo = _undo = [];
    try {
      return body();
    } catch (_) {
      for (final step in undo.reversed) {
        step();
      }
      rethrow;
    } finally {
      _undo = null;
    }
  }

  @override
  IntentRow? intent(IntentId id) => _rows[id];

  @override
  void put(IntentRow row, List<Posting> postings) {
    _remember(row.id);
    _set(row.id, row, postings);
  }

  @override
  void remove(IntentId id) {
    _remember(id);
    _set(id, null, const []);
  }

  void _remember(IntentId id) {
    final row = _rows[id];
    final postings = _postings[id] ?? const <Posting>[];
    _undo?.add(() => _set(id, row, postings));
  }

  void _set(IntentId id, IntentRow? row, List<Posting> postings) {
    final old = _rows[id];
    if (old != null) {
      for (final s in old.streams) {
        _streams[s]?.remove(id);
      }
      final had = _postings.remove(id) ?? const <Posting>[];
      _count -= had.length;
      for (final p in had) {
        _touching[p.account]?.remove(id);
        _byMonth[p.date.monthKey]?.remove(id);
        _addToMonth(p, -1);
      }
      _rows.remove(id);
    }
    if (row == null) return;
    _rows[id] = row;
    for (final s in row.streams) {
      (_streams[s] ??= {}).add(id);
    }
    _postings[id] = List.unmodifiable(postings);
    _count += postings.length;
    for (final p in postings) {
      (_touching[p.account] ??= {}).add(id);
      (_byMonth[p.date.monthKey] ??= {}).add(id);
      _addToMonth(p, 1);
    }
  }

  void _addToMonth(Posting p, int sign) {
    final month = _months[p.date.monthKey] ??= {};
    final key = (p.account, p.currency);
    final was = month[key] ?? (amount: 0, quantity: 0);
    final now = (
      amount: was.amount + sign * p.amount,
      quantity: was.quantity + sign * p.quantity,
    );
    if (now.amount == 0 && now.quantity == 0) {
      month.remove(key);
    } else {
      month[key] = now;
    }
  }

  /// Book order: by day, then the order the intents were kept, then line.
  static int _bookOrder(Posting a, Posting b) {
    final byPlace = comparePositions(
      (date: a.date, seq: a.seq),
      (date: b.date, seq: b.seq),
    );
    if (byPlace != 0) return byPlace;
    final byIntent = a.intent.value.compareTo(b.intent.value);
    return byIntent != 0 ? byIntent : a.line.compareTo(b.line);
  }

  @override
  List<IntentRow> inStream(String stream, {required Position from}) => [
    for (final id in _streams[stream] ?? const <IntentId>{})
      if (comparePositions(_rows[id]!.position, from) >= 0) _rows[id]!,
  ]..sort((a, b) => comparePositions(a.position, b.position));

  @override
  List<Posting> postingsOfIntent(IntentId id) =>
      _postings[id] ?? const <Posting>[];

  @override
  List<Posting> postingsOf(AccountId account, {Position? before}) => [
    for (final id in _touching[account] ?? const <IntentId>{})
      for (final p in _postings[id]!)
        if (p.account == account &&
            (before == null ||
                comparePositions((date: p.date, seq: p.seq), before) < 0))
          p,
  ]..sort(_bookOrder);

  @override
  AccountSums sums({Day? from, Day? until}) {
    final lo = from?.ymd ?? 0;
    final hi = until?.ymd ?? _end;
    final total = <(AccountId, CurrencyCode), AccountSum>{};
    void add((AccountId, CurrencyCode) key, AccountSum sum) =>
        total[key] = addSums(total[key] ?? (amount: 0, quantity: 0), sum);
    for (final MapEntry(key: month, value: sums) in _months.entries) {
      final first = month * 100 + 1;
      final last = Day.stored(first).lastOfMonth.ymd;
      if (last < lo || first > hi) continue;
      if (first >= lo && last <= hi) {
        // A whole month inside the range: its kept sum.
        sums.forEach(add);
        continue;
      }
      for (final id in _byMonth[month] ?? const <IntentId>{}) {
        for (final p in _postings[id]!) {
          if (p.date.monthKey != month || p.date.ymd < lo || p.date.ymd > hi) {
            continue;
          }
          add(
            (p.account, p.currency),
            (amount: p.amount, quantity: p.quantity),
          );
        }
      }
    }
    total.removeWhere((_, s) => s.amount == 0 && s.quantity == 0);
    return total;
  }

  @override
  Map<(String, CurrencyCode), AccountSum> subSums(
    AccountId account, {
    Day? until,
  }) {
    final total = <(String, CurrencyCode), AccountSum>{};
    for (final p in postingsOf(account)) {
      if (until != null && p.date > until) continue;
      final key = (p.sub, p.currency);
      total[key] = addSums(total[key] ?? (amount: 0, quantity: 0), (
        amount: p.amount,
        quantity: p.quantity,
      ));
    }
    return total;
  }

  @override
  List<LedgerAccount> accounts() => List.unmodifiable(_accounts);

  @override
  void keepAccounts(Iterable<LedgerAccount> accounts) {
    final before = _accounts;
    _undo?.add(() => _accounts = before);
    _accounts = [...accounts];
  }

  @override
  void clear() {
    for (final id in [..._rows.keys]) {
      remove(id);
    }
  }

  @override
  int get intentCount => _rows.length;

  @override
  int get postingCount => _count;

  /// Past the last day any book holds.
  static const _end = 99991231;
}
