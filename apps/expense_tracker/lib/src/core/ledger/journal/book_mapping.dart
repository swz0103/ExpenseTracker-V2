import 'package:core/foundation_values.dart' show BusinessDate;
import 'package:domain/credit_cards.dart' show CardSchedule;
import 'package:kernel/kernel.dart';
import 'package:ledger_postings/model/intents.dart';
import 'package:ledger_postings/model/vocabulary.dart';

import '../card_cycle.dart';
import '../models/models.dart';
import 'old_shapes.dart';

/// One record as an intent of the journal: the intent, the accounts it
/// needs that the tree may not have yet (a holding first traded, a
/// category name no category keeps), and the old shapes it has.
typedef Mapped = ({
  LedgerIntent intent,
  List<LedgerAccount> accounts,
  Set<OldShape> shapes,
});

/// The book's records as the journal knows them: its accounts and
/// categories as an account tree, each entry as an intent. What a record
/// means is not worked out again here: an entry's parts are its own
/// (`Entry.amountParts`), a trade's money is `settlementAmount`'s, a
/// card's billing days the card cycle's.
final class BookMapping {
  BookMapping({
    required Iterable<Account> accounts,
    required Iterable<Category> categories,
    Iterable<Holding> start = const [],
    this._entryById = _noEntry,
    this._refundsOf = _noRefunds,
  }) : _accounts = {for (final a in accounts) a.id: a},
       _categories = [...categories],
       _start = [...start] {
    for (final c in _categories) {
      // The first of a name on its side, as the reports read it.
      (c.income ? _incomeIds : _spendingIds).putIfAbsent(c.name, () => c.id);
    }
  }

  /// The entry kept under an id, and the refunds of one: what a refund
  /// of a purchase in instalments cancels is worked out from them.
  final Entry? Function(String id) _entryById;
  final List<Entry> Function(String id) _refundsOf;

  static Entry? _noEntry(String id) => null;
  static List<Entry> _noRefunds(String id) => const [];

  final Map<String, Account> _accounts;
  final List<Category> _categories;
  final List<Holding> _start;

  /// Each category's id by its name, on each side.
  final _incomeIds = <String, String>{};
  final _spendingIds = <String, String>{};

  /// The accounts every intent of the book needs from the start: the
  /// fixed ones, each money account with its pending instalments, each
  /// category on its own side, each stock held from the start.
  List<LedgerAccount> get tree => [
    ...Fixed.all,
    for (final a in _accounts.values) ..._moneyAccounts(a, missing: false),
    for (final c in _categories) _categoryAccount(c),
    for (final h in _start) _holding(h.code),
  ];

  /// When each instalment of a purchase on [account] is billed: the card
  /// cycle's schedule of the account (an account the book does not keep
  /// reads as today, with the default billing days).
  CardSchedule scheduleOf(AccountId account) =>
      _account(account.value.substring(_moneyPrefix.length)).schedule;

  static final _moneyPrefix = moneyAccount('').value;

  Account _account(String id) =>
      _accounts[id] ?? Account(id, id, AccountKind.bank, 0);

  /// What each account and each stock held before the first entry.
  List<LedgerIntent> get openings => [
    for (final a in _accounts.values)
      if (a.opening != 0)
        OpeningBalance(
          id: openingId(a.id),
          seq: 0,
          account: moneyAccount(a.id),
          amount: a.opening,
        ),
    for (final h in _start)
      if (h.shares != 0 || h.cost != 0 || h.realized != 0 || h.dividends != 0)
        OpeningPosition(
          id: IntentId('position:${h.code}'),
          seq: 0,
          code: h.code,
          shares: h.shares,
          cost: h.cost,
          realised: h.realized,
          dividends: h.dividends,
        ),
  ];

  /// The id of what the account [id] held from the start.
  static IntentId openingId(String id) => IntentId('opening:$id');

  /// [e], kept [seq]th, as an intent.
  Mapped map(Entry e, int seq) {
    final accounts = <LedgerAccount>[];
    final shapes = <OldShape>{};
    AccountId money(String id) {
      if (!_accounts.containsKey(id)) {
        shapes.add(OldShape.missingAccount);
        accounts.addAll(_moneyAccounts(_account(id), missing: true));
      }
      return moneyAccount(id);
    }

    AccountId category(String name, {required bool income}) {
      final own = income ? _incomeIds : _spendingIds;
      final other = income ? _spendingIds : _incomeIds;
      if (own[name] case final id?) return categoryAccount(id, income: income);
      if (other.containsKey(name)) {
        shapes.add(
          income
              ? OldShape.incomeUnderSpendingCategory
              : OldShape.spendingUnderIncomeCategory,
        );
      }
      accounts.add(_namedCategoryAccount(name, income: income));
      return namedCategoryAccount(name, income: income);
    }

    final id = IntentId(e.id);
    final date = Day.of(BusinessDate.of(e.date));
    final from = _account(e.account);
    final account = money(e.account);
    final foreign = from.foreign;
    Map<String, Object?> fx(ForeignValue? value) =>
        value == null ? const {} : {Slots.fx: value};
    ForeignValue? worth() {
      if (!foreign) return null;
      if (e.home case final home?) return Worth(home);
      shapes.add(OldShape.foreignWithoutHome);
      return const SameNumber();
    }

    final LedgerIntent intent;
    switch (e.type) {
      case EntryType.expense:
        final instalments = e.installments > 1;
        if (instalments && from.kind != AccountKind.card) {
          shapes.add(OldShape.instalmentsOffCard);
        }
        intent = Spending(
          id: id,
          date: date,
          seq: seq,
          account: account,
          parts: [
            for (final (name, amount) in e.amountParts)
              (category(name, income: false), amount),
          ],
          amendments: {
            ...fx(worth()),
            if (instalments) Slots.instalments: e.installments,
          },
        );
      case EntryType.income:
        final split = e.isRefund ? e.amountParts : const <(String, int)>[];
        intent = Earning(
          id: id,
          date: date,
          seq: seq,
          account: account,
          category: category(e.category, income: !e.isRefund),
          amount: e.amount,
          // A refund gives back by its purchase's split (D65).
          parts: split.length < 2
              ? const []
              : [
                  for (final (name, amount) in split)
                    (category(name, income: false), amount),
                ],
          amendments: {
            ...fx(worth()),
            if (_cancelledBy(e, from) case final cancelled
                when cancelled.isNotEmpty)
              Slots.cancelledInstalments: [
                for (final (day, billed) in cancelled)
                  (Day.of(BusinessDate.of(day)), billed),
              ],
          },
        );
      case EntryType.transfer:
        intent = _transfer(
          e,
          id,
          date,
          seq,
          account,
          money(e.to ?? ''),
          shapes,
          fee: e.fee > 0 ? category(feeCategory, income: false) : null,
        );
      case EntryType.buy || EntryType.sell || EntryType.dividend:
        if (foreign) shapes.add(OldShape.foreignTrade);
        final amendments = fx(foreign ? const SameNumber() : null);
        final code = e.holding;
        if (code != null) accounts.add(_holding(code));
        intent = code == null
            ? _withoutStock(e, id, date, seq, account, amendments, shapes)
            : _trade(e, code, id, date, seq, account, amendments);
    }
    return (intent: intent, accounts: accounts, shapes: shapes);
  }

  /// What the refund [e], kept on [from], changes of what [from] is
  /// billed for the purchase in instalments it gives back, by the card
  /// cycle's rule (`cancelledBy`); empty for any other entry.
  List<(DateTime, int)> _cancelledBy(Entry e, Account from) {
    final of = e.refundOf;
    if (of == null || from.kind != AccountKind.card) return const [];
    final purchase = _entryById(of);
    if (purchase == null) return const [];
    return from.cancelledBy(e, purchase, _refundsOf(of));
  }

  /// [e], a sale or reduction its holdings leave out, as they do today.
  LedgerIntent outOfHoldings(Entry e, LedgerIntent was) => OutOfHoldings(
    id: was.id,
    date: was.date,
    seq: was.seq,
    cash: moneyAccount(e.account),
    settlement: e.settlement,
    reason: OutOfHoldingsReason.oversold,
    amendments: was.amendments,
  );

  LedgerIntent _transfer(
    Entry e,
    IntentId id,
    Day date,
    int seq,
    AccountId from,
    AccountId to,
    Set<OldShape> shapes, {
    required AccountId? fee,
  }) {
    final sender = _account(e.account);
    final receiver = _account(e.to ?? '');
    final across = sender.currency != receiver.currency;
    final foreignFee = e.fee > 0 && sender.foreign;
    if (foreignFee) shapes.add(OldShape.foreignTransferFee);
    if (across && e.received == null) {
      shapes.add(OldShape.crossCurrencyWithoutReceived);
    }
    final ForeignValue? value = switch (e.received) {
      final received? when across && foreignFee => ReceivedFeeSameNumber(
        received,
      ),
      final received? when across => Worth(received),
      _ when across || foreignFee => const SameNumber(),
      _ => null,
    };
    return Transfer(
      id: id,
      date: date,
      seq: seq,
      from: from,
      to: to,
      amount: e.amount,
      fee: e.fee,
      feeCategory: fee,
      amendments: value == null ? const {} : {Slots.fx: value},
    );
  }

  LedgerIntent _trade(
    Entry e,
    String code,
    IntentId id,
    Day date,
    int seq,
    AccountId cash,
    Map<String, Object?> amendments,
  ) => switch (e.type) {
    EntryType.buy => Buy(
      id: id,
      date: date,
      seq: seq,
      cash: cash,
      code: code,
      gross: e.amount,
      shares: e.shares,
      fee: e.fee,
      amendments: amendments,
    ),
    EntryType.sell => Sell(
      id: id,
      date: date,
      seq: seq,
      cash: cash,
      code: code,
      gross: e.amount,
      shares: e.shares,
      fee: e.fee,
      tax: e.tax,
      average: e.average,
      amendments: amendments,
    ),
    _ => Dividend(
      id: id,
      date: date,
      seq: seq,
      cash: cash,
      code: code,
      gross: e.amount,
      shares: e.shares,
      fee: e.fee,
      tax: e.tax,
      split: e.split,
      amendments: amendments,
    ),
  };

  /// A trade naming no stock: a cash dividend is a dividend all the
  /// same; the rest the holdings leave out, as they do today.
  LedgerIntent _withoutStock(
    Entry e,
    IntentId id,
    Day date,
    int seq,
    AccountId cash,
    Map<String, Object?> amendments,
    Set<OldShape> shapes,
  ) {
    if (e.type == EntryType.dividend && !e.isReduction) {
      return Dividend(
        id: id,
        date: date,
        seq: seq,
        cash: cash,
        code: '',
        gross: e.amount,
        fee: e.fee,
        tax: e.tax,
        amendments: amendments,
      );
    }
    shapes.add(OldShape.tradeWithoutStock);
    return OutOfHoldings(
      id: id,
      date: date,
      seq: seq,
      cash: cash,
      settlement: e.settlement,
      reason: OutOfHoldingsReason.noStock,
      amendments: amendments,
    );
  }

  List<LedgerAccount> _moneyAccounts(Account a, {required bool missing}) {
    final id = moneyAccount(a.id);
    final currency = CurrencyCode(a.currency);
    return [
      LedgerAccount(
        id: id,
        cls: classOf(a.kind),
        name: a.name,
        owner: Owners.accounts,
        currency: currency,
        tag: missing ? Tags.missing : a.kind.name,
        inNetWorth: !missing && a.inNetWorth,
      ),
      LedgerAccount(
        id: pendingInstalments(id),
        cls: AccountClass.liability,
        name: a.name,
        owner: Owners.cards,
        currency: currency,
        tag: Tags.pending,
        // Not billed yet, so not owed yet: as net worth reads today.
        inNetWorth: false,
      ),
    ];
  }

  LedgerAccount _categoryAccount(Category c) => LedgerAccount(
    id: categoryAccount(c.id, income: c.income),
    cls: c.income ? AccountClass.income : AccountClass.expense,
    name: c.name,
    owner: Owners.entries,
    tag: Tags.category,
  );

  LedgerAccount _namedCategoryAccount(String name, {required bool income}) =>
      LedgerAccount(
        id: namedCategoryAccount(name, income: income),
        cls: income ? AccountClass.income : AccountClass.expense,
        name: name,
        owner: Owners.entries,
        tag: Tags.category,
      );

  LedgerAccount _holding(String code) => LedgerAccount(
    id: holdingAccount(code),
    cls: AccountClass.asset,
    name: code,
    owner: Owners.investments,
    currency: homeCurrency,
    commodity: code,
    tag: Tags.holding,
  );
}
