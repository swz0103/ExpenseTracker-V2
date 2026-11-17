import 'package:flutter/material.dart';

import '../../../../core/look/glyphs.dart';
import '../../../../core/ledger/ledger.dart';
import '../../../../core/ui/balance_hero.dart';
import '../../../../core/ui/shown_amounts.dart';

/// The month's balance as the page's main tile, with income, spending
/// and dividends along its foot.
class SummarySection extends StatelessWidget {
  const SummarySection({super.key, required this.ledger, required this.month});

  final Ledger ledger;
  final (int, int) month;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ledger,
      builder: (context, _) {
        final (year, m) = month;
        return BalanceHero(
          ledger: ledger,
          icon: Glyph.wallet,
          label: '本月結餘',
          hides: true,
          income: ledger.reportService.income(year, m),
          expense: ledger.reportService.expense(year, m),
          middle: (
            '其中股息',
            ledger.money(ledger.reportService.dividends(year, m)),
          ),
        );
      },
    );
  }
}
