import 'package:flutter/material.dart';

import '../../../core/design_system/findable.dart';
import '../../../core/formatting/setting_topic.dart';
import '../../../core/design_system/glyphs.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/design_system/spacing.dart';
import '../../../core/design_system/shape.dart';

/// 匯出一份 or 還原: a tinted button with an icon.
class ManualBackup extends StatelessWidget {
  const ManualBackup({
    super.key,
    required this.topic,
    required this.glyph,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final SettingTopic topic;
  final Glyph glyph;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = deepOf(color);
    return Findable(
      topic: topic,
      child: ColorCard(
        color: color,
        radius: Radii.large,
        amount: 0.18,
        label: label,
        onTap: onTap,
        padding: const EdgeInsets.symmetric(
          vertical: Space.s4,
          horizontal: Space.s2,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            GlyphIcon(glyph, size: 20, color: ink, tinted: false),
            const SizedBox(width: Space.s2),
            Flexible(
              child: OneLine(
                label,
                style: TextStyle(
                  fontSize: TextSize.title,
                  fontWeight: FontWeight.w800,
                  color: ink,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
