import '../model/accounts.dart';
import '../model/day.dart';
import '../model/ids.dart';
import '../model/posting.dart';
import 'store.dart';

/// A [PostingStore] for posting a whole book afresh, in book order, in
/// memory: what the rules read (each account's postings, each stream's
/// intents) is kept in the order written, so nothing is sorted or looked
/// up twice, and every row is there to be written out at once
/// ([intents], [postings]). Intents are only added: one written again or
/// taken away is not what posting afresh does, and is refused.
final class FreshPostingStore implements PostingStore {
  final _intents = <IntentRow>[];
  final _byId = <IntentId, int>{};
  final _postings = <Posting>[];

  /// Where each intent's postings start in [_postings], by its index.
  final _firstPosting = <int>[];
  final _byAccount = <AccountId, List<Posting>>{};
  final _byStream = <String, List<IntentRow>>{};
  var _accounts = <LedgerAccount>[];
  JournalMark? _mark;
  ({int intents, int postings})? _begun;

  /// Every intent posted, in the order posted.
  List<IntentRow> get intents => List.unmodifiable(_intents);

  /// Every posting, in the order posted.
  List<Posting> get postings => List.unmodifiable(_postings);

  @override
  JournalMark? get mark => _mark;

  @override
  void keepMark(JournalMark mark) => _mark = mark;

  @override
  T transaction<T>(T Function() body) {
    if (_begun != null) throw StateError('nested transaction');
    _begun = (intents: _intents.length, postings: _postings.length);
    try {
      return body();
    } catch (_) {
      _undo(_begun!);
      rethrow;
    } finally {
      _begun = null;
    }
  }

  /// Takes back everything added since [to].
  void _undo(({int intents, int postings}) to) {
    while (_intents.length > to.intents) {
      final row = _intents.removeLast();
      _byId.remove(row.id);
      _firstPosting.removeLast();
      for (final s in row.streams) {
        _byStream[s]!.removeLast();
      }
    }
    while (_postings.length > to.postings) {
      _byAccount[_postings.removeLast().account]!.removeLast();
    }
  }

  @override
  IntentRow? intent(IntentId id) => switch (_byId[id]) {
    final i? => _intents[i],
    null => null,
  };

  @override
  void put(IntentRow row, List<Posting> postings) {
    if (_byId.containsKey(row.id)) {
      throw StateError('posted afresh twice: ${row.id.value}');
    }
    _byId[row.id] = _intents.length;
    _intents.add(row);
    _firstPosting.add(_postings.length);
    for (final s in row.streams) {
      (_byStream[s] ??= []).add(row);
    }
    for (final p in postings) {
      _postings.add(p);
      (_byAccount[p.account] ??= []).add(p);
    }
  }

  @override
  void remove(IntentId id) =>
      throw StateError('nothing is taken away when posting afresh');

  @override
  List<IntentRow> inStream(String stream, {required Position from}) {
    final rows = _byStream[stream] ?? const <IntentRow>[];
    var i = rows.length;
    while (i > 0 && comparePositions(rows[i - 1].position, from) >= 0) {
      i--;
    }
    return rows.sublist(i);
  }

  @override
  List<Posting> postingsOfIntent(IntentId id) {
    final i = _byId[id];
    if (i == null) return const [];
    final end = i + 1 < _firstPosting.length
        ? _firstPosting[i + 1]
        : _postings.length;
    return _postings.sublist(_firstPosting[i], end);
  }

  @override
  List<Posting> postingsOf(AccountId account, {Position? before}) {
    final all = _byAccount[account] ?? const <Posting>[];
    if (before == null) return List.of(all);
    return [
      for (final p in all)
        if (comparePositions((date: p.date, seq: p.seq), before) < 0) p,
    ];
  }

  @override
  List<(Day, int)> daySums(AccountId account) => sumByDay(postingsOf(account));

  @override
  AccountSums sums({Day? from, Day? until}) {
    final total = <(AccountId, CurrencyCode), AccountSum>{};
    for (final p in _postings) {
      if (from != null && p.date < from) continue;
      if (until != null && p.date > until) continue;
      final key = (p.account, p.currency);
      total[key] = addSums(total[key] ?? (amount: 0, quantity: 0), (
        amount: p.amount,
        quantity: p.quantity,
      ));
    }
    return total..removeWhere((_, s) => s.amount == 0 && s.quantity == 0);
  }

  @override
  Map<(String, CurrencyCode), AccountSum> subSums(
    AccountId account, {
    Day? until,
  }) {
    final total = <(String, CurrencyCode), AccountSum>{};
    for (final p in _byAccount[account] ?? const <Posting>[]) {
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
  void keepAccounts(Iterable<LedgerAccount> accounts) =>
      _accounts = [...accounts];

  @override
  void clear() {
    _intents.clear();
    _byId.clear();
    _postings.clear();
    _firstPosting.clear();
    _byAccount.clear();
    _byStream.clear();
    _mark = null;
  }

  @override
  int get intentCount => _intents.length;

  @override
  int get postingCount => _postings.length;
}
