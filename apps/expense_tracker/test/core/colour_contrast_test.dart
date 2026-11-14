import 'package:expense_tracker/src/core/look/kit.dart';
import 'package:expense_tracker/src/core/look/theme.dart';
import 'package:expense_tracker/src/features/settings/ui/settings_hue.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// The colours a card, a category, a tag or a setting is drawn in: words
/// in the deeper [deepOf] read at 4.5:1 on any tint of them up to 0.3,
/// and words on the solid colour ([wordsOn]) at 4.5:1, light and dark.
void main() {
  final colours = <String, Color>{
    for (final (i, c) in Hue.categoryColors.indexed) 'category $i': c,
    for (final (i, c) in nameColors.indexed) 'name $i': c,
    for (final MapEntry(:key, :value) in Palette.all.entries) key: value,
    'backup': SettingsHue.backup,
    'folder': SettingsHue.folder,
    'reminders': SettingsHue.reminders,
    'budget': SettingsHue.budget,
    'daily': SettingsHue.daily,
    'password': SettingsHue.password,
    'recovery': SettingsHue.recovery,
    'trash': SettingsHue.trash,
    'about': SettingsHue.about,
    'warning': SettingsHue.warning,
    'main': SettingsHue.main,
    'accent': Hue.accent,
    'positive': Hue.positive,
    'negative': Hue.negative,
    'investment': Hue.investment,
    'transfer': Hue.transfer,
    'receivable': Hue.receivable,
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
