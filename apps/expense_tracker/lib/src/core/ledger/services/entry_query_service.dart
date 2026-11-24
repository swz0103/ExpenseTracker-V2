import 'package:core/foundation_values.dart' show Currency;
import 'package:core/money/amount_format.dart' show figures;

import '../cache/query_cache.dart';
import 'tracked_readers.dart';
import '../models/models.dart';
import '../repositories/account_repository.dart';
import '../repositories/entry_repository.dart';

/// Questions asked of single entries and of the entries as a whole: a
/// search, what is usual, an entry's group, trades and refunds, and what
/// a merchant was last used with.
final class EntryQueryService {
  EntryQueryService({
    required EntryReader entries,
    required AccountReader accounts,
    required this._cache,
    required this._today,
  }) : _entries = TrackedEntryReader(entries, _cache),
       _accounts = TrackedAccountReader(accounts, _cache);

  final EntryReader _entries;
  final AccountReader _accounts;
  final QueryCache _cache;
  final DateTime Function() _today;

  /// Each entry's words, lower-cased, kept with the entry itself: an
  /// entry never changes, so only one new or edited is worked out again.
  static final _words = Expando<String>('words');

  static String _wordsOf(Entry e) => _words[e] ??= [
    e.note,
    e.merchant,
    e.category,
    ...e.tags,
  ].join('\n').toLowerCase();

  /// Entries of any month whose note, merchant, category or tags hold
  /// [words], or whose amount is [words]; newest first.
  List<Entry> search(String words) =>
      _cache.remember(('search', words), () => _search(words));

  List<Entry> _search(String words) {
    final lower = words.toLowerCase();
    // Each entry's words, lower-cased once per change.
    final texts = _cache.remember(
      'searchText',
      // Exception to as-of-today: a search runs over every entry written.
      () => [for (final e in _entries.all) _wordsOf(e)],
    );
    // Each account's currency, looked up once rather than per entry.
    final currencies = {for (final a in _accounts.all) a.id: a.currency};
    final found = [
      // Exception to as-of-today: a search runs over every entry written.
      for (final (i, e) in _entries.all.indexed)
        if (texts[i].contains(lower) ||
            '${e.amount}' == words ||
            figures(
                  e.amount,
                  Currency.scaleOf(currencies[e.account] ?? homeCode),
                  grouped: false,
                ) ==
                words)
          (i, e),
    ];
    found.sort((a, b) {
      final byDate = b.$2.date.compareTo(a.$2.date);
      return byDate != 0 ? byDate : b.$1.compareTo(a.$1);
    });
    return [for (final (_, e) in found) e];
  }

  /// Known merchants, most used first: a 預定 entry is a use once its
  /// day comes ([countsOn]), and its merchant is known from the start.
  List<String> get merchants =>
      _cache.remember(('merchants', _today()), _merchants);

  List<String> _merchants() {
    final counts = <String, int>{
      // Exception to as-of-today: every merchant written is offered to
      // pick; only the uses below are counted.
      for (final e in _entries.all)
        if (e.merchant.isNotEmpty) e.merchant: 0,
    };
    for (final e in countedOn(_entries.all, _today())) {
      if (e.merchant.isEmpty) continue;
      counts[e.merchant] = (counts[e.merchant] ?? 0) + 1;
    }
    return counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
  }

  /// The category last used with [merchant], if any.
  String? categoryAt(String merchant) => lastAt(merchant)?.category;

  /// The latest spending at [merchant] that counts today ([countsOn]), if
  /// any: what a new entry there starts from (its category and account).
  /// A 預定 entry is not the latest until its day.
  Entry? lastAt(String merchant) => _cache.remember(('lastAt', _today()), () {
    final latest = <String, Entry>{};
    for (final e in countedOn(_entries.all, _today())) {
      if (e.merchant.isEmpty || e.type != EntryType.expense) continue;
      final kept = latest[e.merchant];
      if (kept == null || !e.date.isBefore(kept.date)) latest[e.merchant] = e;
    }
    return latest;
  })[merchant];

  /// Spending recorded alike at least three times in the last 90 days
  /// (the same category, merchant and account), the most often first, at
  /// most [most]: each as its latest entry, which 記一筆 offers to start
  /// from with one tap.
  ///
  /// With [income], income instead, refunds left out. Only entries that
  /// count today ([countsOn]): a 預定 entry is not recent.
  List<Entry> usual({int most = 6, bool income = false}) =>
      _cache.remember(('usual', _today(), most, income), () {
        final since = _today().subtract(const Duration(days: 90));
        final counts = <(String, String, String), int>{};
        final latest = <(String, String, String), Entry>{};
        final kind = income ? EntryType.income : EntryType.expense;
        for (final e in countedOn(_entries.all, _today())) {
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
      });

  /// Transfers made alike again and again lately, the most made first:
  /// the same two accounts and amount, two times or more in 90 days.
  /// Money lent and paid back has its own tab and is left out, and so is
  /// a 預定 transfer ([countsOn]), which is not recent.
  List<Entry> usualTransfers({int most = 4}) =>
      _cache.remember(('usualTransfers', _today(), most), () {
        final since = _today().subtract(const Duration(days: 90));
        final counts = <(String, String, int), int>{};
        final latest = <(String, String, int), Entry>{};
        for (final e in countedOn(_entries.all, _today())) {
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
      });

  /// Every entry written as one with [entry]: a spending first, then
  /// what was paid in it for others; [entry] alone when it has no group.
  List<Entry> groupOf(Entry entry) {
    final group = entry.group;
    if (group == null) return [entry];
    final all = _cache.remember('groups', () {
      final groups = <String, List<Entry>>{};
      // Exception to as-of-today: a group's members are looked up, 預定 or not.
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
    });
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
    // Exception to as-of-today: a holding's list shows every trade, 預定 ones
    // marked.
    for (final e in _entries.all)
      if (e.holding == code) e,
  ]..sort(newestFirst(_entries));

  /// The spending [refund] gives back, while the book holds it; null for
  /// an entry that is not a refund, or none.
  Entry? originalOf(Entry? refund) => switch (refund?.refundOf) {
    final String id => _entries.byId(id),
    null => null,
  };

  /// How much of [original] has been refunded.
  int refunded(Entry original) => original.amount - refundable(original);

  /// How much of [original] is left to refund.
  int refundable(Entry original) =>
      original.amount - _entries.refundedTotal(original.id);
}
