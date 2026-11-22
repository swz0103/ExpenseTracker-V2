import 'package:flutter/material.dart';

import '../../../../../design_system/display/status.dart';
import '../../../../core/design_system/design_system.dart';
import '../../../../core/design_system/spacing.dart';
import '../../../../core/ledger/ledger.dart';
import '../../../../core/navigation/nav.dart';

/// The cards whose bill asks for attention today (due today or overdue),
/// each with the same words as its own page and the account list, and a
/// tap to open it. Nothing when no bill does.
class CardDueSection extends StatelessWidget {
  const CardDueSection({super.key, required this.ledger, required this.nav});

  final Ledger ledger;
  final Nav nav;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ledger.watch(const {Topic.entries, Topic.accounts}),
      builder: (context, _) {
        final rows = [
          for (final card in ledger.accounts.all)
            if (card.kind == AccountKind.card && !card.archived)
              if (cardBillLook(ledger.statementService.billStatus(card))
                  case final look when look.alerts)
                QuoteRow(
                  lead: SquareIcon(look.glyph, look.color, size: 40),
                  title: card.name,
                  detail: look.words,
                  onTap: () => nav.open(AppRoutes.account(card.id)),
                ),
        ];
        if (rows.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: Space.s3),
          child: QuoteBoard(rows),
        );
      },
    );
  }
}
