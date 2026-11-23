import 'package:kernel/kernel.dart';

import '../model/intents.dart';
import '../model/vocabulary.dart';

// How the money kinds post: what an account held from the start, a
// spending, an income or a refund, a transfer. Each line in the paying
// account's currency; a foreign value or instalments are the amenders'.

/// The currency of the money account [account], or a refusal.
(CurrencyCode?, Refused?) _currencyOf(RuleContext context, AccountId account) {
  final currency = context.accounts[account]?.currency;
  return currency == null
      ? (null, Refused('notAMoneyAccount', account.value))
      : (currency, null);
}

final class OpeningBalanceRule implements PostingRule<OpeningBalance> {
  const OpeningBalanceRule();

  @override
  Iterable<String> streams(OpeningBalance intent) => const [];

  @override
  Posted post(OpeningBalance i, RuleContext context) {
    final (currency, refused) = _currencyOf(context, i.account);
    if (currency == null) return refused!;
    return Lines([
      Line(i.account, i.amount, currency),
      Line(Fixed.openingBalances, -i.amount, currency),
    ]);
  }
}

final class SpendingRule implements PostingRule<Spending> {
  const SpendingRule();

  @override
  Iterable<String> streams(Spending intent) => const [];

  @override
  Posted post(Spending i, RuleContext context) {
    final (currency, refused) = _currencyOf(context, i.account);
    if (currency == null) return refused!;
    if (i.parts.isEmpty || i.parts.any((p) => p.$2 < 0)) {
      return const Refused('badAmount');
    }
    final total = i.parts.fold(0, (sum, p) => sum + p.$2);
    return Lines([
      Line(i.account, -total, currency),
      for (final (category, amount) in i.parts)
        Line(category, amount, currency),
    ]);
  }
}

final class EarningRule implements PostingRule<Earning> {
  const EarningRule();

  @override
  Iterable<String> streams(Earning intent) => const [];

  @override
  Posted post(Earning i, RuleContext context) {
    final (currency, refused) = _currencyOf(context, i.account);
    if (currency == null) return refused!;
    if (i.amount < 0) return const Refused('badAmount');
    return Lines([
      Line(i.account, i.amount, currency),
      Line(i.category, -i.amount, currency),
    ]);
  }
}

/// The lines in the sender's currency: a receiving account in another
/// is restated by the foreign-value amender.
final class TransferRule implements PostingRule<Transfer> {
  const TransferRule();

  @override
  Iterable<String> streams(Transfer intent) => const [];

  @override
  Posted post(Transfer i, RuleContext context) {
    final (currency, refused) = _currencyOf(context, i.from);
    if (currency == null) return refused!;
    if (context.accounts[i.to]?.currency == null) {
      return Refused('notAMoneyAccount', i.to.value);
    }
    if (i.amount < 0 || i.fee < 0) return const Refused('badAmount');
    final feeCategory = i.feeCategory;
    if (i.fee > 0 && feeCategory == null) return const Refused('noFeeCategory');
    return Lines([
      Line(i.from, -(i.amount + i.fee), currency),
      Line(i.to, i.amount, currency),
      if (feeCategory != null && i.fee > 0) Line(feeCategory, i.fee, currency),
    ]);
  }
}
