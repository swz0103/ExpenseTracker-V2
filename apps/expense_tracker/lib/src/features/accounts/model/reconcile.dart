import '../../../core/ledger/ledger.dart';

/// The category spending that the book missed goes under when an account
/// is reconciled, and the one money found goes under.
const reconcileSpending = '其他支出';
const reconcileIncome = '其他收入';

/// The note an adjustment carries, so it is told apart in the lists.
const reconcileNote = '對帳調整';

/// What the person counts in [account]: its balance as the bank or the
/// wallet shows it, or for a card or loan what is owed, as a positive
/// amount.
int countedBalance(Account account, int counted) =>
    account.kind.isDebt ? -counted : counted;

/// The book's balance of [account] as the person would count it: what is
/// owed, as a positive amount, for a card or loan.
int shownBalance(Ledger ledger, Account account) {
  final balance = ledger.balance(account.id);
  return account.kind.isDebt ? -balance : balance;
}

/// The entry that brings [account]'s balance to what the person
/// [counted] (as [shownBalance] shows it), dated today: spending when the
/// book has more than is there, income when less. Null when they agree.
/// Accounts in NT$ only: an adjustment elsewhere would need the day's rate.
Entry? reconcile(Ledger ledger, Account account, int counted) {
  if (account.foreign) return null;
  final difference =
      countedBalance(account, counted) - ledger.balance(account.id);
  if (difference == 0) return null;
  final found = difference > 0;
  return Entry(
    id: ledger.newId(),
    date: ledger.today,
    type: found ? EntryType.income : EntryType.expense,
    amount: difference.abs(),
    account: account.id,
    category: found ? reconcileIncome : reconcileSpending,
    note: reconcileNote,
  );
}
