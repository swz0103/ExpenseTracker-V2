import 'package:flutter/material.dart';

import '../theme.dart';
import 'colours.dart';

/// The look of a filled button. With no [ink], the page's own action in
/// [fill]: solid on the light theme, its tint and ring on the dark one,
/// the words in its contrast. With [ink], a quiet button: [fill] behind
/// words in [ink], the same on both themes, such as 恢復 on white.
ButtonStyle solidButton(
  Color fill, {
  Color? ink,
  Size minimumSize = const Size(0, 48),
  double radius = 14,
  EdgeInsetsGeometry? padding,
  TextStyle? words,
}) {
  final quiet = ink != null;
  return FilledButton.styleFrom(
    backgroundColor: quiet ? fill : chosenFill(fill),
    foregroundColor: ink ?? chosenInk(fill),
    disabledBackgroundColor: AppColors.surface,
    side: quiet ? null : chosenEdge(fill),
    minimumSize: minimumSize,
    padding: padding,
    textStyle: words,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
  );
}

/// The look of a button of words alone, in [ink]; on [fill] when given,
/// as a rounded pill.
ButtonStyle wordButton(
  Color ink, {
  Color? fill,
  Size? minimumSize,
  double radius = 22,
  EdgeInsetsGeometry? padding,
  AlignmentGeometry? alignment,
  TextStyle? words,
}) {
  return TextButton.styleFrom(
    foregroundColor: ink,
    backgroundColor: fill,
    minimumSize: minimumSize,
    padding: padding,
    alignment: alignment,
    textStyle: words,
    shape: fill == null
        ? null
        : RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
  );
}
