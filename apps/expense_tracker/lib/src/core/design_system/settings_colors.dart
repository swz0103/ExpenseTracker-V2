import 'theme.dart';

/// The colour of each card on the settings pages; each card, and the
/// panel it opens, is tinted with its own.
abstract final class SettingsColors {
  static const backup = Palette.teal;
  static const folder = Palette.periwinkle;
  static const reminders = Palette.orange;
  static const budget = Palette.green;
  static const daily = Palette.violet;
  static const calendar = Palette.teal;
  static const security = Palette.green;
  static const password = Palette.indigo;
  static const recovery = Palette.gold;
  static const appearance = Palette.violet;
  static const haptics = Palette.orange;
  static const widget = Palette.teal;
  static const sections = Palette.green;
  static const brokerDiscount = Palette.indigo;
  static const importExport = Palette.periwinkle;
  static const csv = Palette.green;
  static const invoice = Palette.gold;
  static const trash = Shade(0xFFA8503E, 0xFFC2867A);
  static const about = Palette.slate;

  /// 上次備份 and 關於's main card, in the interface colour.
  static const main = AppColors.accent;

  /// The main card when a backup is overdue or none is on.
  static const warning = Palette.gold;
}
