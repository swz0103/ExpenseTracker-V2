import '../../../core/ledger/amounts.dart';
import '../../../core/ledger/ledger.dart';

/// What the account form holds while it is filled in, and what saving
/// it does to the ledger: a new account, or the changes to [old] with
/// its balance set to what was typed. The screen only shows it.
final class AccountForm {
  AccountForm(this.ledger, {this.old})
    : name = old?.name ?? '',
      balance = _startBalance(ledger, old),
      limit = '${old?.limit ?? ''}',
      kind = old?.kind ?? AccountKind.bank,
      icon = old?.icon,
      closing = old?.closingDay ?? 1,
      due = old?.dueDay ?? 15,
      counted = old?.inNetWorth ?? true,
      currency = old?.currency ?? homeCode,
      principal = '${old?.principal ?? ''}';

  final Ledger ledger;

  /// The account being changed; null for a new one.
  final Account? old;

  String name;

  /// The balance as typed: what is owed, for a card or loan.
  String balance;

  /// A card's credit limit as typed.
  String limit;
  AccountKind kind;
  String? icon;
  int closing;
  int due;

  /// Whether the account counts in net worth.
  bool counted;

  /// Chosen when the account is opened; fixed after that.
  String currency;

  /// A loan's amount when taken out, as typed.
  String principal;

  /// The account a new loan's money went into; null when only the debt
  /// is kept.
  String? fundInto;

  /// A debt is shown as what is owed: a card at −500 reads 500, and one
  /// overpaid by 300 reads −300.
  static String _startBalance(Ledger ledger, Account? account) {
    if (account == null) return '';
    final balance = ledger.balance(account.id);
    return plainIn(account.kind.isDebt ? -balance : balance, account.currency);
  }

  /// Cards and loans are kept in NT$.
  bool get foreignAllowed => !kind.isDebt;

  bool get card => kind == AccountKind.card;

  bool get loan => kind == AccountKind.loan;

  /// Why the account cannot be saved yet; null when it can.
  String? get problem => name.trim().isEmpty ? '請輸入帳戶名稱' : null;

  /// The balance typed, in the ledger's sign; null when left empty, which
  /// keeps the balance of an account being changed.
  int? get typedBalance {
    final typed = minorOf(balance, foreignAllowed ? currency : homeCode);
    if (typed == null) return null;
    return kind.isDebt ? -typed : typed;
  }

  /// A loan's amount when taken out, from what was typed; null when left
  /// empty or not a loan.
  int? get typedPrincipal => loan ? minorOf(principal, homeCode) : null;

  /// The place after every placed account, so a new one comes last on
  /// 我的帳戶; null while none has been placed.
  int? get _nextPlace {
    int? last;
    for (final a in ledger.accounts) {
      final place = a.place;
      if (place != null && (last == null || place > last)) last = place;
    }
    return last == null ? null : last + 1;
  }

  /// A new loan whose money went into [fundInto] opens at nothing owed;
  /// the transfer [save] adds then sets what is owed.
  bool get _funded => old == null && loan && fundInto != null;

  /// The account as the form now stands.
  Account build() {
    final before = old;
    final terms = (
      closingDay: card ? closing : null,
      dueDay: card ? due : null,
      limit: card ? int.tryParse(limit.trim()) : null,
    );
    if (before == null) {
      return Account(
        ledger.newId(),
        name.trim(),
        kind,
        _funded ? 0 : typedBalance ?? 0,
        icon: icon,
        closingDay: terms.closingDay,
        dueDay: terms.dueDay,
        limit: terms.limit,
        inNetWorth: counted,
        currency: foreignAllowed ? currency : homeCode,
        principal: typedPrincipal,
        place: kind == AccountKind.loan || kind == AccountKind.receivable
            ? null
            : _nextPlace,
      );
    }
    return Account(
      before.id,
      name.trim(),
      kind,
      before.opening,
      icon: icon,
      closingDay: terms.closingDay,
      dueDay: terms.dueDay,
      limit: terms.limit,
      archived: before.archived,
      inNetWorth: counted,
      currency: before.currency,
      closes: before.closes,
      history: before.history,
      principal: typedPrincipal,
      place: before.place,
    );
  }

  /// Writes the account to the ledger; false when it cannot be saved.
  bool save() {
    if (problem != null) return false;
    final account = build();
    if (old == null) {
      ledger.addAccount(account);
      final into = fundInto;
      final owed = typedBalance;
      if (_funded && into != null && owed != null && owed < 0) {
        ledger.add(
          Entry(
            id: ledger.newId(),
            date: ledger.today,
            type: EntryType.transfer,
            amount: -owed,
            account: account.id,
            category: transferCategory,
            note: '${account.name}撥款',
            to: into,
          ),
        );
      }
      return true;
    }
    ledger.updateAccount(account);
    final typed = typedBalance;
    if (typed != null && typed != ledger.balance(account.id)) {
      ledger.setBalance(account.id, typed);
    }
    return true;
  }

  /// The transfer that settles [account] before it is archived: what is
  /// left moves to [into], or a debt is paid from it.
  static Entry settlement(Ledger ledger, Account account, String into) {
    final left = ledger.balance(account.id);
    return Entry(
      id: ledger.newId(),
      date: ledger.today,
      type: EntryType.transfer,
      amount: left.abs(),
      account: left > 0 ? account.id : into,
      category: transferCategory,
      note: '${account.name}結清',
      to: left > 0 ? into : account.id,
    );
  }
}
