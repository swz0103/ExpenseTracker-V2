import 'day.dart';
import 'ids.dart';
import 'quantity.dart';

/// One line a posting rule gives: [amount] in the smallest unit of
/// [currency] on [account], positive a debit (an asset or a spending
/// grows), negative a credit. Dated [date], or the intent's day when
/// null (an instalment billed later is not). [quantity] counts units of
/// what the account holds (shares, in [quantityScale] parts, exactly),
/// none for money; [sub] is a key within the account (a lot of a
/// holding).
final class Line {
  Line(
    this.account,
    this.amount,
    this.currency, {
    this.date,
    BigInt? quantity,
    this.sub = '',
  }) : quantity = quantity ?? noQuantity;

  final AccountId account;
  final int amount;
  final CurrencyCode currency;
  final Day? date;
  final BigInt quantity;
  final String sub;

  /// This line for [amount] of [currency] instead, all else kept.
  Line restated(int amount, CurrencyCode currency) =>
      Line(account, amount, currency, date: date, quantity: quantity, sub: sub);
}

/// A kept posting: line [line] of intent [intent], which stands at
/// [seq] among the intents of its day.
final class Posting {
  Posting({
    required this.intent,
    required this.line,
    required this.account,
    required this.amount,
    required this.currency,
    required this.date,
    required this.seq,
    BigInt? quantity,
    this.sub = '',
  }) : quantity = quantity ?? noQuantity;

  final IntentId intent;
  final int line;
  final AccountId account;
  final int amount;
  final CurrencyCode currency;
  final Day date;
  final int seq;
  final BigInt quantity;
  final String sub;

  @override
  bool operator ==(Object other) =>
      other is Posting &&
      other.intent == intent &&
      other.line == line &&
      other.account == account &&
      other.amount == amount &&
      other.currency == currency &&
      other.date == date &&
      other.seq == seq &&
      other.quantity == quantity &&
      other.sub == sub;

  @override
  int get hashCode => Object.hash(
    intent,
    line,
    account,
    amount,
    currency,
    date,
    seq,
    quantity,
    sub,
  );

  @override
  String toString() =>
      'Posting(${intent.value}#$line ${date.ymd} ${account.value} '
      '$amount ${currency.value} q$quantity $sub)';
}
