import 'package:accounts/accounts.dart';
import 'package:app_core/app_core.dart';
import 'package:categories/categories.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:merchants/merchants.dart';
import 'package:tags/tags.dart';

import 'bookkeeping.dart';

/// Income and expense reported for one month in one currency.
final class MonthTotal {
  const MonthTotal(this.income, this.expense);

  final Money income;
  final Money expense;
}

/// Everything committed so far. A transaction works on a copy and replaces
/// this only when its body succeeds.
final class _State {
  _State();

  _State.copy(_State other)
    : operations = Map.of(other.operations),
      outbox = List.of(other.outbox),
      events = List.of(other.events),
      accounts = Map.of(other.accounts),
      postings = Map.of(other.postings),
      order = List.of(other.order),
      metadata = Map.of(other.metadata),
      notes = Map.of(other.notes),
      categories = Map.of(other.categories),
      tags = Map.of(other.tags),
      merchants = Map.of(other.merchants);

  Map<OperationKey, RecordedOperation> operations = {};
  List<OutboxMessage> outbox = [];
  List<String> events = [];
  Map<PublicId, Account> accounts = {};
  Map<PublicId, Posting> postings = {};
  List<PublicId> order = [];
  Map<PublicId, PostingMetadata> metadata = {};
  Map<PublicId, EntryNote> notes = {};
  Map<PublicId, Category> categories = {};
  Map<PublicId, Tag> tags = {};
  Map<PublicId, Merchant> merchants = {};
}

/// Bookkeeping kept in memory. Balances and monthly totals are computed from
/// the postings on every read, so this is also the reference the SQLCipher
/// projections are checked against. Nothing survives a restart.
final class MemoryBookkeeping
    implements UnitOfWork<MemoryBookkeepingTransaction> {
  var _state = _State();
  bool _writing = false;

  @override
  Future<R> write<R>(
    Future<R> Function(MemoryBookkeepingTransaction transaction) body,
  ) async {
    if (_writing) throw StateError('Overlapping write transactions.');
    _writing = true;
    final transaction = MemoryBookkeepingTransaction._(_State.copy(_state));
    try {
      final result = await body(transaction);
      _state = transaction._state;
      return result;
    } finally {
      transaction._open = false;
      _writing = false;
    }
  }

  int get eventCount => _state.events.length;

  List<Account> accounts(WorkspaceId workspace) => [
    for (final account in _state.accounts.values)
      if (account.workspace == workspace) account,
  ];

  Money balance(Account account) =>
      _balance(_state, account.id, account.currency);

  /// Postings in [workspace], newest first.
  List<Posting> postings(WorkspaceId workspace) => [
    for (final id in _state.order.reversed)
      if (_state.postings[id]!.operation.workspace == workspace)
        _state.postings[id]!,
  ];

  List<Category> categories(WorkspaceId workspace) => [
    for (final row in _state.categories.values)
      if (row.workspace == workspace) row,
  ];

  /// Totals for `YYYY-MM`, keyed by currency code.
  Map<String, MonthTotal> monthly(WorkspaceId workspace, String month) {
    final totals = <String, MonthTotal>{};
    for (final posting in postings(workspace)) {
      if (!posting.date.toString().startsWith(month)) continue;
      final income = posting.reportIncome;
      final expense = posting.reportExpense;
      if (income.minorUnits == BigInt.zero &&
          expense.minorUnits == BigInt.zero) {
        continue;
      }
      final earlier = totals[income.currency.code];
      totals[income.currency.code] = earlier == null
          ? MonthTotal(income, expense)
          : MonthTotal(earlier.income + income, earlier.expense + expense);
    }
    return totals;
  }
}

final class MemoryBookkeepingTransaction implements BookkeepingTransaction {
  MemoryBookkeepingTransaction._(this._state);

  final _State _state;
  bool _open = true;

  _State get _live {
    if (!_open) throw StateError('Transaction already finished.');
    return _state;
  }

  @override
  Future<RecordedOperation?> findOperation(OperationKey key) async =>
      _live.operations[key];

  @override
  Future<void> recordOperation(RecordedOperation operation) async {
    if (_live.operations.containsKey(operation.key)) {
      throw StateError('Operation recorded twice.');
    }
    _live.operations[operation.key] = operation;
  }

  @override
  Future<void> enqueue(OutboxMessage message) async =>
      _live.outbox.add(message);

  @override
  Future<void> appendEvent({
    required PublicId id,
    required WorkspaceId workspace,
    required String kind,
    required String payload,
  }) async => _live.events.add(kind);

  @override
  Future<Account?> account(PublicId id) async => _live.accounts[id];

  @override
  Future<void> saveAccount(Account account) async =>
      _live.accounts[account.id] = account;

  @override
  Future<Posting?> posting(PublicId id) async => _live.postings[id];

  @override
  Future<bool> isReversed(PublicId postingId) async =>
      _live.postings.values.any((p) => p.reversalOf == postingId);

  @override
  Future<bool> isLocked(PublicId postingId) async => false;

  @override
  Future<List<Posting>> refundsOf(PublicId expenseId) async => [
    for (final id in _live.order)
      if (_live.postings[id]!.refundOf == expenseId) _live.postings[id]!,
  ];

  @override
  Future<Posting?> openingOf(PublicId accountId) async {
    for (final id in _live.order) {
      final posting = _live.postings[id]!;
      if (posting.kind == PostingKind.opening &&
          posting.legs.single.account.id == accountId &&
          !await isReversed(posting.id)) {
        return posting;
      }
    }
    return null;
  }

  @override
  Future<EntryNote> noteOf(PublicId postingId) async =>
      _live.notes[postingId] ?? const EntryNote(0, '');

  @override
  Future<void> saveNote(PublicId postingId, EntryNote note) async =>
      _live.notes[postingId] = note;

  @override
  Future<Money> balance(PublicId accountId, Currency currency) async =>
      _balance(_live, accountId, currency);

  @override
  Future<bool> hasUnsettledItems(PublicId accountId) async => false;

  @override
  Future<PostingMetadata> postingMetadata(PublicId postingId) async =>
      _live.metadata[postingId] ?? PostingMetadata.none;

  @override
  Future<void> savePosting(Posting posting, PostingMetadata metadata) async {
    if (_live.postings.containsKey(posting.id)) {
      throw StateError('Posting saved twice.');
    }
    _live.postings[posting.id] = posting;
    _live.order.add(posting.id);
    _live.metadata[posting.id] = metadata;
  }

  @override
  Future<List<Category>> categories(WorkspaceId workspace) async => [
    for (final row in _live.categories.values)
      if (row.workspace == workspace) row,
  ];

  @override
  Future<void> saveCategory(Category category) async =>
      _live.categories[category.id] = category;

  @override
  Future<List<Tag>> tags(WorkspaceId workspace) async => [
    for (final row in _live.tags.values)
      if (row.workspace == workspace) row,
  ];

  @override
  Future<void> saveTag(Tag tag) async => _live.tags[tag.id] = tag;

  @override
  Future<List<Merchant>> merchants(WorkspaceId workspace) async => [
    for (final row in _live.merchants.values)
      if (row.workspace == workspace) row,
  ];

  @override
  Future<void> saveMerchant(Merchant merchant) async =>
      _live.merchants[merchant.id] = merchant;
}

Money _balance(_State state, PublicId accountId, Currency currency) {
  var total = BigInt.zero;
  for (final posting in state.postings.values) {
    for (final leg in posting.legs) {
      if (leg.account.id == accountId) total += leg.amount.minorUnits;
    }
  }
  return Money(currency, total);
}
