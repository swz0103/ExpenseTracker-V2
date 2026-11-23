import 'package:flutter/material.dart';

import '../design_system/app_mark.dart';
import '../design_system/keys.dart';
import '../design_system/theme.dart';

/// Draws the app's mark on its paper over everything the app shows,
/// sheets and dialogs included, while [covered]: the ledger may not be
/// seen (the lock gate says when). What is under it then takes no taps
/// and is not read out. Put above every route (MaterialApp's builder).
class LockCover extends StatelessWidget {
  const LockCover({super.key, required this.covered, required this.child});

  final bool covered;
  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      // The same wrappers covered or not, so the screens under keep
      // their state.
      ExcludeSemantics(
        excluding: covered,
        child: AbsorbPointer(absorbing: covered, child: child),
      ),
      if (covered)
        const ColoredBox(
          key: Keys.lockCover,
          color: AppColors.paper,
          child: Center(child: AppMark(size: 72)),
        ),
    ],
  );
}
