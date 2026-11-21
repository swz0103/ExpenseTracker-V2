import '../../../core/ledger/ledger.dart';

/// What [person] owes in all, as a positive amount or nothing.
int owedFrom(BalanceService balances, Account person) {
  final balance = balances.balance(person.id);
  return balance > 0 ? balance : 0;
}

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
