import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../theme.dart';

// Tints, deeper words and colours picked from a name.

/// [color] mixed into the paper: the flat tint of a card in that colour.
/// The same mix on the dark paper gives the dark card.
Color tintOf(Color color, [double amount = 0.2]) =>
    Color.lerp(Hue.paper, color, Shade.dark ? amount + 0.08 : amount)!;

/// [color] a step deeper for words on its own tint, or a step lighter on
/// the dark theme: as little as reads at 4.5:1 on a tint of up to 0.3.
Color deepOf(Color color) {
  final toward = Shade.dark ? const Color(0xFFFFFFFF) : _darkWords;
  final under = tintOf(color, 0.3);
  for (var amount = Shade.dark ? 0.35 : 0.3; amount < 1; amount += 0.05) {
    final words = Color.lerp(color, toward, amount)!;
    if (contrastOf(words, under) >= 4.5) return words;
  }
  return toward;
}

/// Words on a solid [fill]: white where white reads at 4.5:1, otherwise
/// near black, as on the accent in the dark theme.
Color wordsOn(Color fill) => contrastOf(const Color(0xFFFFFFFF), fill) >= 4.5
    ? const Color(0xFFFFFFFF)
    : const Color(0xFF0F1A1F);

const _darkWords = Color(0xFF1A2228);

/// How far apart [a] and [b] read, as WCAG counts it: 1 to 21.
double contrastOf(Color a, Color b) {
  final (x, y) = (a.computeLuminance(), b.computeLuminance());
  return (x > y ? x + 0.05 : y + 0.05) / (x > y ? y + 0.05 : x + 0.05);
}

/// A colour picked from [name], the same each time: for what has no
/// colour of its own, such as a tag, a merchant, a person or a loan.
Color nameColor(String name) {
  var sum = 0;
  for (final unit in name.codeUnits) {
    sum = (sum * 31 + unit) & 0x7fffffff;
  }
  return nameColors[sum % nameColors.length];
}

/// The colours [nameColor] picks from, light and dark.
const nameColors = [
  Palette.orange,
  Palette.rose,
  Palette.green,
  Palette.gold,
  Palette.periwinkle,
  Palette.teal,
  Palette.violet,
  Palette.blue,
];
