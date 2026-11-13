import '../../../core/look/theme.dart';

/// The colour of each card on the settings pages; each card, and the
/// panel it opens, is tinted with its own.
abstract final class SettingsHue {
  static const backup = Shade(0xFF4E8A9A, 0xFF86B5C1);
  static const folder = Shade(0xFF7686B8, 0xFFA5B1D8);
  static const reminders = Shade(0xFFD08B5B, 0xFFE3AA82);
  static const budget = Shade(0xFF5C9A83, 0xFF8CC3AE);
  static const daily = Shade(0xFF8E7CC0, 0xFFB5A8DD);
  static const calendar = Shade(0xFF4E8A9A, 0xFF86B5C1);
  static const security = Shade(0xFF5C9A83, 0xFF8CC3AE);
  static const password = Shade(0xFF4A5D99, 0xFF9FAEE0);
  static const recovery = Shade(0xFFC9A34A, 0xFFDDBE73);
  static const appearance = Shade(0xFF8E7CC0, 0xFFB5A8DD);
  static const haptics = Shade(0xFFD08B5B, 0xFFE3AA82);
  static const widget = Shade(0xFF4E8A9A, 0xFF86B5C1);
  static const sections = Shade(0xFF5C9A83, 0xFF8CC3AE);
  static const exchange = Shade(0xFF7686B8, 0xFFA5B1D8);
  static const csv = Shade(0xFF5C9A83, 0xFF8CC3AE);
  static const invoice = Shade(0xFFC9A34A, 0xFFDDBE73);
  static const trash = Shade(0xFFA8503E, 0xFFE0907E);
  static const about = Shade(0xFF6B767C, 0xFFA3AEB3);

  /// 上次備份 and 關於's main card, in the interface colour.
  static const main = Hue.accent;

  /// The main card when a backup is overdue or none is on.
  static const warning = Shade(0xFFC9A34A, 0xFFDDBE73);
}
