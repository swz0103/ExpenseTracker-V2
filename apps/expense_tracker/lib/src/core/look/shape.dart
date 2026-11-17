/// The corner radii every rounded thing takes, from Material 3's shape
/// scale, named as it names them. Pages pick a step, never a number, so
/// the same kind of thing is rounded alike everywhere.
abstract final class Radii {
  /// Tiny marks: a bar's ends, a dot, a badge.
  static const extraSmall = 4.0;

  /// Chips, small buttons, a field's corners.
  static const small = 8.0;

  /// Rows in a group, a mark's tile, a picker's cell.
  static const medium = 12.0;

  /// Cards and colour blocks: the app's main surface.
  static const large = 16.0;

  /// A large card's outer corners.
  static const largeIncreased = 20.0;

  /// Sheets and the biggest panels.
  static const extraLarge = 28.0;

  static const extraLargeIncreased = 32.0;

  static const extraExtraLarge = 48.0;

  /// Fully round: a pill or a circle, whatever its size.
  static const full = 999.0;
}
