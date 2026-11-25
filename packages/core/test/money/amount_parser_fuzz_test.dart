import 'dart:io';
import 'dart:math';

import 'package:core/money/amount_parser.dart';
import 'package:core/money/typed_text.dart';
import 'package:test/test.dart';

/// R12: texts made at random (seeded) read as amounts against an oracle
/// of the documented grammar: never thrown, and what is taken is what the
/// grammar says. A few thousand cases here; `FUZZ_CASES=200000` for a
/// nightly run.
void main() {
  final cases = int.tryParse(Platform.environment['FUZZ_CASES'] ?? '') ?? 5000;
  final grammar = RegExp(r'^([-−+]?)(\d{1,3}(?:,\d{3})+|\d+)(?:\.(\d*))?$');

  /// What a strict reading of [text] says, or null when it is not the
  /// grammar or has more decimals than [scale] that are not zeros.
  BigInt? oracle(String text, int scale) {
    final m = grammar.firstMatch(text.trim());
    if (m == null) return null;
    final whole = m[2]!.replaceAll(',', '');
    final fraction = m[3] ?? '';
    if (fraction.length > scale &&
        fraction.substring(scale).contains(RegExp('[1-9]'))) {
      return null;
    }
    final kept = fraction.length > scale
        ? fraction.substring(0, scale)
        : fraction.padRight(scale, '0');
    final value = BigInt.parse('$whole$kept');
    return m[1] == '-' || m[1] == '−' ? -value : value;
  }

  const pool = [
    '0', '1', '2', '5', '9', ',', '.', '-', '+', '−', '​', '‏', //
    '﻿', ' ', '　', '\t', '\n', '１', '．', '－', 'e', 'x', r'NT$', '%',
    '\u0000', '\uD800', '😀',
  ];

  test('$cases texts: an amount the grammar gives, or why not', () {
    final r = Random(12012);
    for (var i = 0; i < cases; i++) {
      final text = [
        for (var k = 0, n = r.nextInt(14); k < n; k++)
          pool[r.nextInt(pool.length)],
      ].join();
      for (final scale in [0, 2]) {
        switch (parseAmount(text, scale: scale)) {
          case AmountOk(:final minor):
            expect(minor.abs(), lessThanOrEqualTo(maxMinorUnits(scale)));
            expect(BigInt.from(minor), oracle(text, scale), reason: text);
          case AmountRefused():
            final o = oracle(text, scale);
            if (o != null) {
              expect(
                o.abs() > BigInt.from(maxMinorUnits(scale)) ||
                    (scale == 0 && text.contains('.')),
                isTrue,
                reason: 'refused "$text"',
              );
            }
        }
      }
      expect(halfWidth(halfWidth(text)), halfWidth(text));
      expect(plainText(plainText(text)), plainText(text));
    }
  });
}
