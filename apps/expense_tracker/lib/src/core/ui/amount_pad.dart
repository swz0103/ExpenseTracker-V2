import 'package:flutter/material.dart';

import '../look/glyphs.dart';
import '../look/haptics.dart';
import '../look/theme.dart';
import '../look/widgets.dart';

/// Number keys laid in a form, for an amount typed without opening the
/// calculator: digits, + and −, ⌫ and C. Each key goes to [onKey], to be
/// taken by [AmountKeys]. × and ÷ stay on the calculator, which the
/// amount still opens.
class AmountPad extends StatelessWidget {
  const AmountPad({super.key, required this.onKey, this.decimal = false});

  final ValueChanged<String> onKey;

  /// Whether the amount takes decimals: `.` in place of `000`.
  final bool decimal;

  static const _gap = 6.0;
  static const _height = 46.0;

  @override
  Widget build(BuildContext context) {
    final rows = [
      ['7', '8', '9', '⌫'],
      ['4', '5', '6', '+'],
      ['1', '2', '3', '−'],
      ['00', '0', if (decimal) '.' else '000', 'C'],
    ];
    return Column(
      children: [
        for (final (i, row) in rows.indexed) ...[
          if (i > 0) const SizedBox(height: _gap),
          SizedBox(
            height: _height,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (j, key) in row.indexed) ...[
                  if (j > 0) const SizedBox(width: _gap),
                  Expanded(child: _key(key)),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _key(String key) {
    final side = '+−⌫C'.contains(key);
    return Pressable(
      depth: 0.93,
      child: Material(
        color: side ? Hue.hero : Hue.tile,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            Haptics.selection();
            onKey(key);
          },
          child: Center(
            child: key == '⌫'
                ? Semantics(
                    label: '退格',
                    child: const GlyphIcon(
                      Glyph.backspace,
                      size: 22,
                      color: Hue.accent,
                    ),
                  )
                : Text(
                    key,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w500,
                      color: side ? Hue.accent : Hue.ink,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
