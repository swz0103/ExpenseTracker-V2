import 'package:expense_tracker/src/core/design_system/components.dart';
import 'package:expense_tracker/src/core/design_system/theme.dart';
import 'package:expense_tracker/src/core/design_system/settings_colors.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// The colours a card, a category, a tag or a setting is drawn in: words
/// in the deeper [deepOf] read at 4.5:1 on any tint of them up to 0.3,
/// and words on the solid colour ([wordsOn]) at 4.5:1, light and dark.
void main() {
  final colours = <String, Color>{
    for (final (i, c) in AppColors.categoryColors.indexed) 'category $i': c,
    for (final (i, c) in nameColors.indexed) 'name $i': c,
    for (final MapEntry(:key, :value) in Palette.all.entries) key: value,
    'backup': SettingsColors.backup,
    'folder': SettingsColors.folder,
    'reminders': SettingsColors.reminders,
    'budget': SettingsColors.budget,
    'daily': SettingsColors.daily,
    'password': SettingsColors.password,
    'recovery': SettingsColors.recovery,
    'trash': SettingsColors.trash,
    'about': SettingsColors.about,
    'warning': SettingsColors.warning,
    'main': SettingsColors.main,
    'accent': AppColors.accent,
    'positive': AppColors.positive,
    'negative': AppColors.negative,
    'investment': AppColors.investment,
    'transfer': AppColors.transfer,
    'receivable': AppColors.receivable,
  };

  tearDown(() => Shade.dark = false);

  for (final dark in [false, true]) {
    test(
      'words on coloured cards read at 4.5:1, ${dark ? 'dark' : 'light'}',
      () {
        Shade.dark = dark;
        final faults = <String>[];
        for (final MapEntry(key: name, value: colour) in colours.entries) {
          for (final amount in const [0.14, 0.2, 0.25, 0.3]) {
            final ratio = contrastOf(deepOf(colour), tintOf(colour, amount));
            if (ratio < 4.5) {
              faults.add(
                '$name on its $amount tint: ${ratio.toStringAsFixed(2)}',
              );
            }
          }
          final solid = contrastOf(wordsOn(colour), colour);
          if (solid < 4.5) {
            faults.add('words on $name: ${solid.toStringAsFixed(2)}');
          }
        }
        expect(faults, isEmpty, reason: faults.join('\n'));
      },
    );
  }
}
