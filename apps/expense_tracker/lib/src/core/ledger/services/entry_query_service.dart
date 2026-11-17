import '../../text/amounts.dart';
import '../cache/query_cache.dart';
import '../cache/topic.dart';
import '../models/models.dart';
import '../repositories/account_repository.dart';
import '../repositories/entry_repository.dart';

/// Questions asked of single entries and of the entries as a whole: a
/// search, what is usual, an entry's group, trades and refunds, and what
/// a merchant was last used with.
final class EntryQueryService {
  EntryQueryService({
    required this._entries,
    required this._accounts,
    required this._cache,
    required this._today,
  });

  final EntryReader _entries;
  final AccountReader _accounts;
  final QueryCache _cache;
  final DateTime Function() _today;

  /// Entries of any month whose note, merchant, category or tags hold
  /// [words], or whose amount is [words]; newest first.
  List<Entry> search(String words) => _cache.remember(
    ('search', words),
    () => _search(words),
    reads: const {Topic.entries, Topic.accounts, Topic.categories},
  );

  List<Entry> _search(String words) {
    final lower = words.toLowerCase();
    // Each entry's words, lower-cased once per change.
    final texts = _cache.remember(
      'searchText',
      () => [
        for (final e in _entries.all)
          [e.note, e.merchant, e.category, ...e.tags].join('\n').toLowerCase(),
      ],
      reads: const {Topic.entries},
    );
    final found = [
      for (final (i, e) in _entries.all.indexed)
        if (texts[i].contains(lower) ||
            '${e.amount}' == words ||
            plainIn(e.amount, _accounts.resolve(e.account).currency) == words)
          (i, e),
    ];
    found.sort((a, b) {
      final byDate = b.$2.date.compareTo(a.$2.date);
      return byDate != 0 ? byDate : b.$1.compareTo(a.$1);
    });
    return [for (final (_, e) in found) e];
  }

  /// Known merchants, most used first.
  List<String> get merchants =>
      _cache.remember('merchants', _merchants, reads: const {Topic.entries});

  List<String> _merchants() {
    final counts = <String, int>{};
    for (final e in _entries.all) {
      if (e.merchant.isEmpty) continue;
      counts[e.merchant] = (counts[e.merchant] ?? 0) + 1;
    }
    return counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
  }

  /// The category last used with [merchant], if any.
  String? categoryAt(String merchant) => lastAt(merchant)?.category;

  /// The latest spending at [merchant], if any: what a new entry there
  /// starts from (its category and account).
  Entry? lastAt(String merchant) => _cache.remember('lastAt', () {
    final latest = <String, Entry>{};
    for (final e in _entries.all) {
      if (e.merchant.isEmpty || e.type != EntryType.expense) continue;
      final kept = latest[e.merchant];
      if (kept == null || !e.date.isBefore(kept.date)) latest[e.merchant] = e;
    }
    return latest;
  }, reads: const {Topic.entries})[merchant];

  /// Spending recorded alike at least three times in the last 90 days
  /// (the same category, merchant and account), the most often first, at
  /// most [most]: each as its latest entry, which 記一筆 offers to start
  /// from with one tap.
  ///
  /// With [income], income instead, refunds left out.
  List<Entry> usual({int most = 6, bool income = false}) =>
      _cache.remember(('usual', _today(), most, income), () {
        final since = _today().subtract(const Duration(days: 90));
        final counts = <(String, String, String), int>{};
        final latest = <(String, String, String), Entry>{};
        final kind = income ? EntryType.income : EntryType.expense;
        for (final e in _entries.all) {
          if (e.type != kind ||
              e.refundOf != null ||
              e.date.isBefore(since) ||
              e.parts.isNotEmpty ||
              e.installments > 1 ||
              e.home != null) {
            continue;
          }
          final key = (e.category, e.merchant, e.account);
          counts[key] = (counts[key] ?? 0) + 1;
          final kept = latest[key];
          if (kept == null || !e.date.isBefore(kept.date)) latest[key] = e;
        }
        final keys = [
          for (final MapEntry(:key, :value) in counts.entries)
            if (value >= 3) key,
        ]..sort((a, b) => counts[b]!.compareTo(counts[a]!));
        return [for (final key in keys.take(most)) latest[key]!];
      }, reads: const {Topic.entries});

  /// Transfers made alike again and again lately, the most made first:
  /// the same two accounts and amount, two times or more in 90 days.
  /// Money lent and paid back has its own tab and is left out.
  List<Entry> usualTransfers({int most = 4}) =>
      _cache.remember(('usualTransfers', _today(), most), () {
        final since = _today().subtract(const Duration(days: 90));
        final counts = <(String, String, int), int>{};
        final latest = <(String, String, int), Entry>{};
        for (final e in _entries.all) {
          final to = e.to;
          if (e.type != EntryType.transfer ||
              to == null ||
              e.date.isBefore(since) ||
              _accounts.resolve(e.account).kind == AccountKind.receivable ||
              _accounts.resolve(to).kind == AccountKind.receivable) {
            continue;
          }
          final key = (e.account, to, e.amount);
          counts[key] = (counts[key] ?? 0) + 1;
          final kept = latest[key];
          if (kept == null || !e.date.isBefore(kept.date)) latest[key] = e;
        }
        final keys = [
          for (final MapEntry(:key, :value) in counts.entries)
            if (value >= 2) key,
        ]..sort((a, b) => counts[b]!.compareTo(counts[a]!));
        return [for (final key in keys.take(most)) latest[key]!];
      }, reads: const {Topic.entries, Topic.accounts});

  /// Every entry written as one with [entry]: a spending first, then
  /// what was paid in it for others; [entry] alone when it has no group.
  List<Entry> groupOf(Entry entry) {
    final group = entry.group;
    if (group == null) return [entry];
    final all = _cache.remember('groups', () {
      final groups = <String, List<Entry>>{};
      for (final e in _entries.all) {
        final key = e.group;
        if (key != null) (groups[key] ??= []).add(e);
      }
      for (final members in groups.values) {
        members.sort(
          (a, b) => (a.type == EntryType.expense ? 0 : 1).compareTo(
            b.type == EntryType.expense ? 0 : 1,
          ),
        );
      }
      return groups;
    }, reads: const {Topic.entries});
    return all[group] ?? [entry];
  }

  /// The entry that stands for its group in a list: the spending, or the
  /// first of the group when it has none.
  Entry groupLead(Entry entry) => groupOf(entry).first;

  /// One of a group that its lead stands for in a list.
  bool isGroupTail(Entry entry) =>
      entry.group != null && groupLead(entry).id != entry.id;

  /// Every trade and dividend of [code], newest first.
  List<Entry> tradesOf(String code) => [
    for (final e in _entries.all)
      if (e.holding == code) e,
  ]..sort((a, b) => b.date.compareTo(a.date));

  /// How much of [original] has been refunded.
  int refunded(Entry original) => original.amount - refundable(original);

  /// How much of [original] is left to refund.
  int refundable(Entry original) =>
      original.amount - _entries.refundedTotal(original.id);
}
