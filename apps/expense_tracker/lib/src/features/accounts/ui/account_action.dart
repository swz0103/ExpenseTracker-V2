import 'package:flutter/material.dart';

import '../../../core/look/glyphs.dart';
import '../../../core/look/spacing.dart';
import '../../../core/look/theme.dart';
import '../../../core/look/widgets.dart';

/// One of an account's actions in the row under its balance, such as 記一筆
/// or 對帳: the same tile on every account's page.
class AccountAction extends StatelessWidget {
  const AccountAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final Glyph icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GroupBox(
      padding: const EdgeInsets.symmetric(
        vertical: Space.s2,
        horizontal: Space.s1,
      ),
      onTap: onTap,
      child: Column(
        children: [
          SquareIcon(icon, Hue.accent, size: 30),
          const SizedBox(height: Space.s1),
          Text(
            label,
            maxLines: 1,
            style: const TextStyle(
              fontSize: TextSize.body,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
