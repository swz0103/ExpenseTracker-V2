part of 'debts_page.dart';

/// How much of a loan is paid, as a ring with the share in the middle.
class _PaidRing extends StatelessWidget {
  const _PaidRing({required this.share, required this.color, this.size = 64});

  final double share;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: Stack(
      fit: StackFit.expand,
      children: [
        CircularProgressIndicator(
          value: share,
          strokeWidth: size / 9,
          strokeCap: StrokeCap.round,
          color: color,
          backgroundColor: tintOf(color, 0.3),
        ),
        Center(
          child: Text(
            '${(share * 100).round()}%',
            textScaler: TextScaler.noScaling,
            style: TextStyle(
              fontSize: size / 4,
              fontWeight: FontWeight.w800,
              color: deepOf(color),
            ),
          ),
        ),
      ],
    ),
  );
}

/// A loan: how much is paid as a ring, its name and amount taken out,
/// and what is left, on its colour's tint.
class _LoanCard extends StatelessWidget {
  const _LoanCard({
    required this.ledger,
    required this.loan,
    required this.onTap,
  });

  final Ledger ledger;
  final Account loan;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final share = paidShare(ledger.balanceService, loan);
    final principal = loan.principal;
    final color = nameColor(loan.name);
    final ink = deepOf(color);
    final owed = ledger.orDots(
      groupDigits(owedOn(ledger.balanceService, loan)),
    );
    return ColorCard(
      color: color,
      onTap: onTap,
      // Its name first, then what is owed, as a screen reader should say
      // it; the ring's share last.
      label: [
        loan.name,
        if (principal != null) '原借 ${ledger.orDots(groupDigits(principal))}',
        '尚欠 $owed',
        if (share != null) '已還 ${(share * 100).round()}%',
      ].join('，'),
      padding: const EdgeInsets.fromLTRB(
        Space.s4,
        Space.s4,
        Space.s4,
        Space.s4,
      ),
      child: Row(
        children: [
          if (share != null)
            _PaidRing(share: share, color: color)
          else
            SquareIcon(Glyph.loan, color, size: 52),
          const SizedBox(width: Space.s4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  loan.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: TextSize.title,
                    fontWeight: FontWeight.w800,
                    color: ink,
                  ),
                ),
                if (principal != null)
                  OneLine(
                    '原借 ${ledger.orDots(groupDigits(principal))}',
                    style: TextStyle(fontSize: TextSize.small, color: ink),
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '尚欠',
                style: TextStyle(fontSize: TextSize.caption, color: ink),
              ),
              Text(
                owed,
                style: const TextStyle(
                  fontSize: TextSize.heading,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
