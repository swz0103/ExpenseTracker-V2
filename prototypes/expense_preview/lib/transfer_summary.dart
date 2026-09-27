import 'package:flutter/material.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger_generation_probe/ledger_store.dart';

import 'money_view.dart';
import 'privacy_presentation.dart';

/// Both sides and fee remain distinguishable, including when amounts are hidden.
class TransferSummary extends StatelessWidget {
  const TransferSummary({
    super.key,
    required this.entry,
    required this.source,
    required this.destination,
    required this.privacy,
  });
  final LedgerEntry entry;
  final String source, destination;
  final PrivacyMode privacy;
  @override
  Widget build(BuildContext context) {
    final principal = Money(entry.amount.currency, -entry.amount.minorUnits);
    final fee = entry.fee!;
    Widget amount(String label, Money money, String suffix) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label),
        MoneyView(
          key: ValueKey('transfer-$suffix-${entry.id}'),
          money: money,
          privacy: privacy,
          kind: MoneyKind.transaction,
        ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '轉帳 · $source → $destination',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Text(entry.date.toString()),
        if (entry.received != null &&
            entry.received!.currency != principal.currency)
          amount('轉出本金', principal, 'source-principal'),
        amount('轉入本金', entry.received ?? principal, 'principal'),
        if (entry.received != null &&
            entry.received!.currency != principal.currency)
          const Text('換算依據：實際轉出、轉入本金（未使用行情報價）。'),
        amount('手續費支出', fee, 'fee'),
        amount('轉出合計', principal + fee, 'total'),
      ],
    );
  }
}
