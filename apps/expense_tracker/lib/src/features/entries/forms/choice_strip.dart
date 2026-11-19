import 'package:flutter/material.dart';

import '../../../core/design_system/theme.dart';
import '../../../core/design_system/spacing.dart';
import 'compose_widgets.dart';

// A row of choices that slides sideways, its last one pinned.

/// A row of [ChoiceStripItem]s that slides sideways, with [pinned] kept still
/// at its right end after a thin line, so it is never pushed out of view.
class ChoiceStrip extends StatelessWidget {
  const ChoiceStrip({super.key, required this.items, this.pinned});

  final List<Widget> items;
  final Widget? pinned;

  @override
  Widget build(BuildContext context) {
    final still = pinned;
    return Padding(
      padding: const EdgeInsets.only(top: Space.s2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: items),
            ),
          ),
          if (still != null) ...[
            // Centred on the 50 dp squares beside it, not on their words.
            Container(
              width: 1,
              height: 34,
              margin: const EdgeInsets.only(
                top: Space.s2,
                left: Space.s1,
                right: Space.s1,
              ),
              color: AppColors.line,
            ),
            still,
          ],
        ],
      ),
    );
  }
}
