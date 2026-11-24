import 'dart:math' show max;

import '../../../core/ledger/ledger.dart';

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
