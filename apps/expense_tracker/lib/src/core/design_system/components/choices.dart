import 'package:flutter/widgets.dart';

import '../controls.dart';
import '../glyphs.dart';
import '../shape.dart';
import '../theme.dart';
import 'colours.dart';

// The two ways a form offers a look to choose: a colour, and an icon.
// Every form uses these, so a choice looks and reads out the same
// wherever it is made.

/// The side of the square a choice may be tapped in: Material's least
/// touch target.
const _target = 48.0;

/// A colour to choose: a dot in it, the one chosen ringed in ink with a
/// tick in the colour's own contrast.
class SwatchButton extends StatelessWidget {
  const SwatchButton({
    super.key,
    required this.color,
    required this.selected,
    required this.onTap,
    this.label = '顏色',
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  /// What a screen reader calls it, with whether it is chosen.
  final String label;

  @override
  Widget build(BuildContext context) {
    return TapArea(
      label: label,
      selected: selected,
      onTap: onTap,
      child: SizedBox.square(
        dimension: _target,
        child: Center(
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? AppColors.ink : const Color(0x00000000),
                width: 3,
              ),
            ),
            child: selected
                ? GlyphIcon(Glyph.check, size: 20, color: wordsOn(color))
                : null,
          ),
        ),
      ),
    );
  }
}

/// An icon to choose, on a rounded square: the one chosen solid in
/// [color] with the icon white, the others on [background] in grey.
class IconChoiceButton extends StatelessWidget {
  const IconChoiceButton({
    super.key,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
    this.label,
    this.size = 44,
    this.background,
  });

  final Glyph icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  /// What a screen reader calls it.
  final String? label;

  /// The side of the square; it is tapped in at least 48 dp.
  final double size;

  /// Under an icon not chosen; [AppColors.surface] when null, white on a grey
  /// group.
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final side = size < _target ? _target : size;
    return TapArea(
      label: label,
      selected: selected,
      onTap: onTap,
      child: SizedBox.square(
        dimension: side,
        child: Center(
          child: IconChoiceSquare(
            icon: icon,
            color: color,
            selected: selected,
            size: size,
            background: background,
          ),
        ),
      ),
    );
  }
}

/// How an [IconChoiceButton] looks, for a choice whose tap area holds
/// more, such as the icon's name under it.
class IconChoiceSquare extends StatelessWidget {
  const IconChoiceSquare({
    super.key,
    required this.icon,
    required this.color,
    required this.selected,
    this.size = 44,
    this.background,
  });

  final Glyph icon;
  final Color color;
  final bool selected;
  final double size;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: selected ? color : (background ?? AppColors.surface),
        borderRadius: BorderRadius.circular(Radii.medium),
      ),
      alignment: Alignment.center,
      child: GlyphIcon(
        icon,
        size: size * 0.5,
        color: selected ? AppColors.onSolid : AppColors.muted,
        tinted: !selected,
      ),
    );
  }
}
