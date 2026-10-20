import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

/// The code points [font] draws: read from its `cmap` table (format 4,
/// Windows Unicode BMP).
Set<int> _coverage(Uint8List font) {
  final data = ByteData.sublistView(font);
  final tables = data.getUint16(4);
  var cmap = -1;
  for (var i = 0; i < tables; i++) {
    final record = 12 + 16 * i;
    final tag = String.fromCharCodes(font.sublist(record, record + 4));
    if (tag == 'cmap') cmap = data.getUint32(record + 8);
  }
  expect(cmap, greaterThan(0), reason: 'no cmap table');
  final subtables = data.getUint16(cmap + 2);
  for (var i = 0; i < subtables; i++) {
    final entry = cmap + 4 + 8 * i;
    if (data.getUint16(entry) != 3 || data.getUint16(entry + 2) != 1) continue;
    final table = cmap + data.getUint32(entry + 4);
    if (data.getUint16(table) != 4) continue;
    final segments = data.getUint16(table + 6) ~/ 2;
    final ends = table + 14;
    final starts = ends + 2 * segments + 2;
    final deltas = starts + 2 * segments;
    final offsets = deltas + 2 * segments;
    final covered = <int>{};
    for (var s = 0; s < segments; s++) {
      final end = data.getUint16(ends + 2 * s);
      final start = data.getUint16(starts + 2 * s);
      final delta = data.getUint16(deltas + 2 * s);
      final rangeOffset = data.getUint16(offsets + 2 * s);
      for (var c = start; c <= end && c != 0xFFFF; c++) {
        final int glyph;
        if (rangeOffset == 0) {
          glyph = (c + delta) & 0xFFFF;
        } else {
          final at = offsets + 2 * s + rangeOffset + 2 * (c - start);
          final raw = data.getUint16(at);
          glyph = raw == 0 ? 0 : (raw + delta) & 0xFFFF;
        }
        if (glyph != 0) covered.add(c);
      }
    }
    return covered;
  }
  fail('no Windows Unicode cmap');
}

void main() {
  test('the Chinese font draws every Chinese character the screens use', () {
    final covered = _coverage(
      File('fonts/Huninn-Regular.ttf').readAsBytesSync(),
    );
    final missing = <String>{};
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      for (final rune in file.readAsStringSync().runes) {
        // CJK ideographs and full-width punctuation: what the system
        // font would otherwise draw in another style.
        final chinese =
            (rune >= 0x3000 && rune <= 0x303F) ||
            (rune >= 0x4E00 && rune <= 0x9FFF) ||
            (rune >= 0xFF00 && rune <= 0xFFEF);
        if (chinese && !covered.contains(rune)) {
          missing.add(String.fromCharCode(rune));
        }
      }
    }
    expect(missing, isEmpty);
  });
}
