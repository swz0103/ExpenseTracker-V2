import 'package:flutter/material.dart';

import '../../../../core/look/figures.dart';
import '../../../../core/look/glyphs.dart';
import '../../../../core/look/theme.dart';
import '../../../../core/look/widgets.dart';
import '../../../../core/ledger/ledger.dart';

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
          income: ledger.income(year, m),
          expense: ledger.expense(year, m),
          third: (
            Glyph.dividend,
            '其中股息',
            ledger.money(ledger.dividends(year, m)),
            Hue.investment,
          ),
        );
      },
    );
  }
}
