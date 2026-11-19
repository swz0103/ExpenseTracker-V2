import 'package:flutter/material.dart';

import '../../../core/design_system/glyphs.dart';
import '../../../core/design_system/shape.dart';
import '../../../core/design_system/spacing.dart';
import '../../../core/design_system/theme.dart';
import '../../../core/design_system/motion.dart';

/// Fields that fold away under one line: [closed] says what is in them,
/// a tap on it ([onToggle]) opens or closes them, and [body] shows while
/// [open]. While [viewing] an entry there is nothing to open or close:
/// [body] shows, with no heading repeating it. [headingKey] marks the
/// line to tap.
class FieldsFold extends StatelessWidget {
  const FieldsFold({
    super.key,
    this.headingKey,
    required this.closed,
    required this.open,
    required this.viewing,
    required this.onToggle,
    required this.body,
  });

  final Key? headingKey;
  final String closed;
  final bool open;
  final bool viewing;
  final VoidCallback onToggle;
  final List<Widget> body;

  @override
  Widget build(BuildContext context) {
    if (viewing) {
      return Padding(
        padding: const EdgeInsets.only(top: Space.s1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: body,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: Space.s1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _heading(),
          MotionSize(
            duration: Motion.short4,
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: open
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: body,
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  Widget _heading() => InkWell(
    key: headingKey,
    borderRadius: BorderRadius.circular(Radii.medium),
    onTap: onToggle,
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.s1,
        vertical: Space.s3,
      ),
      child: Row(
        children: [
          const GlyphIcon(Glyph.note, size: 18, color: AppColors.muted),
          const SizedBox(width: Space.s2),
          Expanded(
            child: Text(
              closed,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: TextSize.body,
                fontWeight: open ? FontWeight.w700 : FontWeight.w600,
                color: open ? AppColors.ink : AppColors.muted,
              ),
            ),
          ),
          RotatedBox(
            quarterTurns: open ? 3 : 1,
            child: const GlyphIcon(
              Glyph.next,
              size: 16,
              color: AppColors.faint,
            ),
          ),
        ],
      ),
    ),
  );
}
