import 'package:kernel/kernel.dart';
import 'package:ledger_entries/model.dart' show AccountKind, homeCode;

// The accounts, owners, tags and streams today's records post to: one
// place for every word two of them must agree on.

/// The currency the book is kept in, as the journal names it.
const homeCurrency = CurrencyCode(homeCode);

/// Who registers what: the owners the modules of phase 4 will be.
abstract final class Owners {
  static const accounts = OwnerId('accounts');
  static const entries = OwnerId('entries');
  static const cards = OwnerId('cards');
  static const fx = OwnerId('fx');
  static const investments = OwnerId('investments');

  /// Accounts kept only so that an old book posts as it reads today.
  static const legacy = OwnerId('legacy');
}

/// The owners' words for their accounts ([LedgerAccount.tag]).
abstract final class Tags {
  /// A category: an income or spending account.
  static const category = 'category';

  /// A card's (or any account's) instalments not billed yet.
  static const pending = 'pending';

  /// One stock's shares.
  static const holding = 'holding';

  /// An account an entry names that the book does not keep.
  static const missing = 'missing';

  /// Where money moves to and from: an account kind, or a missing one.
  static final money = {for (final k in AccountKind.values) k.name, missing};
}

/// The journal's class of a money account of [kind]: what is owed is a
/// liability.
AccountClass classOf(AccountKind kind) =>
    kind.isDebt ? AccountClass.liability : AccountClass.asset;

/// The account of the book's money account [id].
AccountId moneyAccount(String id) => AccountId('acct:$id');

/// Where the instalments of purchases on [account] wait to be billed.
AccountId pendingInstalments(AccountId account) =>
    AccountId('${account.value}:instalments');

/// The account of the category [name] on the income side or the
/// spending side. By name, as the records name categories and the
/// reports count them: a category deleted since keeps its account, and
/// a name used on both sides (income under a spending category) is two
/// accounts, each counted as today.
AccountId categoryAccount(String name, {required bool income}) =>
    AccountId('cat:${income ? 'income' : 'spending'}:$name');

/// The account of the stock [code]'s shares.
AccountId holdingAccount(String code) => AccountId('holding:$code');

/// The accounts every book has.
abstract final class Fixed {
  /// What accounts held before the first record.
  static const openingBalances = AccountId('equity:opening');

  /// What stocks held before the first record cost.
  static const openingPositions = AccountId('equity:positions');

  /// The far side of every conversion between currencies.
  static const currencyTrading = AccountId('equity:trading');

  /// Gains and losses on shares sold, by stock (sub key): income to an
  /// accountant, not to today's income report.
  static const realisedGains = AccountId('income:realised');

  /// Dividends, by stock (sub key).
  static const dividends = AccountId('income:dividends');

  /// The other side of trades an old book keeps but its holdings leave
  /// out (sold more than was held, or naming no stock).
  static const outOfHoldings = AccountId('equity:out-of-holdings');

  static const all = [
    LedgerAccount(
      id: openingBalances,
      cls: AccountClass.equity,
      name: 'opening balances',
      owner: Owners.accounts,
    ),
    LedgerAccount(
      id: openingPositions,
      cls: AccountClass.equity,
      name: 'opening positions',
      owner: Owners.investments,
    ),
    LedgerAccount(
      id: currencyTrading,
      cls: AccountClass.equity,
      name: 'currency trading',
      owner: Owners.fx,
    ),
    LedgerAccount(
      id: realisedGains,
      cls: AccountClass.income,
      name: 'realised gains',
      owner: Owners.investments,
      inFlowReports: false,
    ),
    LedgerAccount(
      id: dividends,
      cls: AccountClass.income,
      name: 'dividends',
      owner: Owners.investments,
    ),
    LedgerAccount(
      id: outOfHoldings,
      cls: AccountClass.equity,
      name: 'trades out of holdings',
      owner: Owners.legacy,
    ),
  ];
}

/// The streams whose intents read the ones before them.
abstract final class Streams {
  /// One stock's trades: a sale reads the lots before it.
  static String holding(String code) => 'holding:$code';

  /// One account's instalment purchases: billed by its schedule, so a
  /// change of the schedule posts them again.
  static String instalments(AccountId account) =>
      'instalments:${account.value}';
}

/// The rules' own words for why an intent is refused ([Refused.code]).
abstract final class Refusals {
  static const notAMoneyAccount = 'notAMoneyAccount';
  static const badAmount = 'badAmount';
  static const noFeeCategory = 'noFeeCategory';
  static const noHoldingAccount = 'noHoldingAccount';

  /// A sale or reduction of more shares than are held before it.
  static const oversold = 'oversold';
  static const quantityTooLarge = 'quantity.tooLarge';
  static const fxNeeded = 'fx.needed';
  static const fxUnused = 'fx.unused';
  static const fxBadAmount = 'fx.badAmount';
  static const fxAmbiguous = 'fx.ambiguous';
  static const fxBadValue = 'fx.badValue';
  static const instalmentsCount = 'instalments.count';
  static const instalmentsNotOneAccount = 'instalments.notOneAccount';
  static const instalmentsNoSchedule = 'instalments.noSchedule';
}

/// The slots amendments are kept under.
abstract final class Slots {
  /// What an amount in another currency is worth: a [ForeignValue].
  static const fx = 'fx';

  /// How many instalments a purchase is billed in: an int, 2 or more.
  static const instalments = 'instalments';
}
