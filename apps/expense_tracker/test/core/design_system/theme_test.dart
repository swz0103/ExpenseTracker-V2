import 'package:expense_tracker/src/core/design_system/settings_colors.dart';
import 'package:expense_tracker/src/core/design_system/theme.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every colour drawn as a fill takes its dark value from one rule,
/// [darkFill], so the dark theme's fills are all equally bright.
void main() {
  final fills = <String, Shade>{
    ...Palette.all,
    for (final (i, s) in AppColors.shades.indexed) 'shade $i': s,
    'cash': AppColors.cash,
    'bank': AppColors.bank,
    'wallet': AppColors.wallet,
    'card': AppColors.card,
    'holdings': AppColors.holdings,
    'trash': SettingsColors.trash,
  };

  test('each fill\'s dark value is darkFill of its light one', () {
    final faults = <String>[];
    for (final MapEntry(key: name, value: shade) in fills.entries) {
      final want = Color(darkFill(shade.light));
      final got = Color(shade.darkValue);
      final off = [
        (want.r - got.r).abs(),
        (want.g - got.g).abs(),
        (want.b - got.b).abs(),
      ].reduce((a, b) => a > b ? a : b);
      if (off > 2 / 255) {
        faults.add(
          '$name: 0x${shade.darkValue.toRadixString(16)}, rule gives '
          '0x${want.toARGB32().toRadixString(16)}',
        );
      }
    }
    expect(faults, isEmpty, reason: faults.join('\n'));
  });

  test('a fill reads at the same contrast on a dark card', () {
    final card = Color(AppColors.white.darkValue).computeLuminance() + 0.05;
    for (final light in [0xFFC9A34A, 0xFF4A5D99, 0xFF9F4535, 0xFF5C9A83]) {
      final shown = Color(darkFill(light)).computeLuminance() + 0.05;
      expect(shown / card, closeTo(darkFillContrast, 0.05));
    }
  });

  test('marks keep their colour on the light theme', () {
    expect(markOf(AppColors.positive), AppColors.positive);
    Shade.dark = true;
    addTearDown(() => Shade.dark = false);
    expect(
      markOf(AppColors.positive).toARGB32(),
      darkFill(AppColors.positive.light),
    );
  });
}
