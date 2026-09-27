import 'package:flutter/material.dart';
import 'package:foundation_values/foundation_values.dart';

import 'privacy_presentation.dart';

class MoneyView extends StatelessWidget {
  const MoneyView({
    super.key,
    required this.money,
    required this.privacy,
    required this.kind,
  });
  final Money money;
  final PrivacyMode privacy;
  final MoneyKind kind;
  @override
  Widget build(BuildContext context) {
    final value = presentMoney(money, privacy, kind);
    return Semantics(
      label: value.label,
      child: ExcludeSemantics(child: Text(value.text)),
    );
  }
}

/// Narrow screens and large fonts put amounts below the label instead of
/// squeezing an unbounded ListTile trailing amount into the remaining width.
class FinancialSummary extends StatelessWidget {
  const FinancialSummary({
    super.key,
    required this.title,
    required this.subtitle,
    required this.money,
    required this.privacy,
    required this.kind,
    required this.moneyKey,
    this.action,
  });
  final String title, subtitle;
  final Money money;
  final PrivacyMode privacy;
  final MoneyKind kind;
  final Key moneyKey;
  final Widget? action;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final detail = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          Text(subtitle),
        ],
      );
      final amount = MoneyView(
        key: moneyKey,
        money: money,
        privacy: privacy,
        kind: kind,
      );
      if (constraints.maxWidth < 520 ||
          MediaQuery.textScalerOf(context).scale(16) > 20) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            detail,
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(child: amount),
                ?action,
              ],
            ),
          ],
        );
      }
      return Row(
        children: [
          Expanded(flex: 2, child: detail),
          const SizedBox(width: 16),
          Flexible(child: amount),
          ?action,
        ],
      );
    },
  );
}
