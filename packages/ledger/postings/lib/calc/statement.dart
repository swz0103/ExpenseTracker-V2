import 'package:kernel/kernel.dart';

import '../model/vocabulary.dart';

/// What is still to pay on the statement of [card] that closed on
/// [closed], as of [asOf], from the card's postings: what it owed then,
/// less what was paid in since, up to [asOf] (a payment dated later is
/// 預定, decision D25, and not paid yet). A payment is money brought in
/// from another money account (another leg of the same intent takes
/// money out of one); a refund or a reward is not, and counts towards the
/// next statement.
int statementDue(
  AccountId card,
  Day closed,
  BookReader book, {
  required Day asOf,
}) {
  var owed = 0;
  var paid = 0;
  for (final p in book.postings(card)) {
    if (p.date <= closed) {
      owed -= p.amount;
    } else if (p.date <= asOf && p.amount > 0 && _isPayment(p, book)) {
      paid += p.amount;
    }
  }
  final due = owed - paid;
  return due < 0 ? 0 : due;
}

bool _isPayment(Posting credit, BookReader book) => book
    .legs(credit.intent)
    .any(
      (leg) =>
          leg.account != credit.account &&
          leg.amount < 0 &&
          Tags.money.contains(book.accounts[leg.account]?.tag),
    );
