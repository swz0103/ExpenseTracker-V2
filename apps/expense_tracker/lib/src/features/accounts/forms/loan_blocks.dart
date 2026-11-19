part of 'account_editor.dart';

/// An account the loan is paid from or went into, as a block: its mark
/// and name, or what having none means.
class _AccountBlock extends StatelessWidget {
  const _AccountBlock({
    required this.label,
    required this.account,
    required this.empty,
    required this.onTap,
  });

  final String label;
  final Account? account;
  final String empty;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final account = this.account;
    final color = account == null ? Hue.faint : accountHue(account);
    return ColorCard(
      color: color,
      amount: account == null ? 0.22 : 0.2,
      radius: Radii.largeIncreased,
      onTap: onTap,
      label: '$label，${account?.name ?? empty}',
      padding: const EdgeInsets.fromLTRB(
        Space.s3,
        Space.s3,
        Space.s2,
        Space.s3,
      ),
      child: Row(
        children: [
          SquareIcon(
            account == null ? Glyph.other : accountIcon(account),
            color,
            size: 40,
          ),
          const SizedBox(width: Space.s2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                OneLine(label, style: mutedSmall),
                Text(
                  account?.name ?? empty,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: TextSize.body,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
