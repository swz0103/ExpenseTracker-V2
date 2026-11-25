import 'dart:math' show max;

import '../../../core/ledger/ledger.dart';

/// The people paid for, most owed first in NT\$ (each at home, so a
/// person kept in US\$ is not ranked by their cents), open ones only.
List<Account> peopleOwing(AccountReader accounts, BalanceService balances) {
  return [
    for (final a in accounts.open)
      if (a.kind == AccountKind.receivable) a,
  ]..sort((a, b) => balances.worthOf(b).compareTo(balances.worthOf(a)));
}

/// What the open people owe in all, in whole NT\$: the one figure 更多
/// and 代墊與借貸 both show ([owedFromAll] of [peopleOwing]).
int owedByPeople(AccountReader accounts, BalanceService balances) =>
    owedFromAll(balances, peopleOwing(accounts, balances));

/// The open loans.
List<Account> openLoans(AccountReader accounts) => [
  for (final a in accounts.open)
    if (a.kind == AccountKind.loan) a,
];

/// Whole days from [day] to [today].
int daysSince(DateTime today, DateTime day) {
  final days = today.difference(day).inDays;
  return days < 0 ? 0 : days;
}

/// What [person] owes in all, as a positive amount or nothing.
int owedFrom(BalanceService balances, Account person) {
  final balance = balances.balance(person.id);
  return balance > 0 ? balance : 0;
}

/// What [people] owe in all, in whole NT$: each one's balance at home
/// ([BalanceService.worthOf]), so a person kept in US$ is not added as
/// though their cents were NT$.
int owedFromAll(BalanceService balances, Iterable<Account> people) =>
    people.fold(0, (sum, a) => sum + max(0, balances.worthOf(a)));

/// What is left on [loans] in all, in whole NT$, each at home.
int owedOnAll(BalanceService balances, Iterable<Account> loans) =>
    loans.fold(0, (sum, a) => sum + max(0, -balances.worthOf(a)));

/// What is left on [loan], as a positive amount or nothing.
int owedOn(BalanceService balances, Account loan) {
  final balance = balances.balance(loan.id);
  return balance < 0 ? -balance : 0;
}

/// How much of [loan] is paid, 0 to 1; null without its amount when taken
/// out.
double? paidShare(BalanceService balances, Account loan) {
  final principal = loan.principal;
  if (principal == null || principal <= 0) return null;
  final share = (principal - owedOn(balances, loan)) / principal;
  return share < 0 ? 0.0 : (share > 1 ? 1.0 : share);
}
