import 'package:flutter/material.dart';

import '../../../core/design_system/glyphs.dart';
import '../../../core/widgets/icons.dart';
import '../../../core/design_system/theme.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/ledger/ledger.dart';
import '../../../core/design_system/shape.dart';
import '../../../core/design_system/spacing.dart';

/// An account the loan is paid from or went into, as a block: its mark
/// and name, or what having none means.
class AccountBlock extends StatelessWidget {
  const AccountBlock({
    super.key,
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
    final color = account == null ? AppColors.faint : accountColor(account);
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
