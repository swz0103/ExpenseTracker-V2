import 'package:foundation_values/foundation_values.dart';

/// A current Ledger balance, never a second persisted balance or valuation.
final class AssetBalanceFact {
  const AssetBalanceFact(this.accountId, this.balance, this.included);
  final PublicId accountId;
  final Money balance;
  final bool included;
}

final class AssetCurrencySummary {
  const AssetCurrencySummary(this.currency, this.total, this.accounts);
  final Currency currency;
  final Money total;
  final List<AssetBalanceFact> accounts;
}

/// Cash and bank balances only. A cross-currency net worth requires an actual
/// valuation source, so this report intentionally has no grand total.
final class AssetReport {
  AssetReport._(this.currencies, this.excludedCount);
  final List<AssetCurrencySummary> currencies;
  final int excludedCount;

  factory AssetReport.build(Iterable<AssetBalanceFact> source) {
    final ids = <PublicId>{};
    final grouped = <Currency, List<AssetBalanceFact>>{};
    var excluded = 0;
    for (final fact in source) {
      if (!ids.add(fact.accountId)) {
        throw const FormatException('Duplicate account balance.');
      }
      if (fact.included) {
        grouped.putIfAbsent(fact.balance.currency, () => []).add(fact);
      } else {
        excluded++;
      }
    }
    final currencies = grouped.keys.toList()
      ..sort((a, b) {
        final code = a.code.compareTo(b.code);
        return code != 0 ? code : a.scale.compareTo(b.scale);
      });
    return AssetReport._(
      List.unmodifiable([
        for (final currency in currencies)
          AssetCurrencySummary(
            currency,
            Money(
              currency,
              grouped[currency]!.fold<BigInt>(
                BigInt.zero,
                (sum, fact) => sum + fact.balance.minorUnits,
              ),
            ),
            List.unmodifiable(grouped[currency]!),
          ),
      ]),
      excluded,
    );
  }
}
