import 'dart:convert' show utf8;

import 'big5_table.dart';

/// How the bytes of a file were written as text.
enum TextEncoding { utf8, big5 }

/// The text of a file chosen to import, or why it cannot be read.
sealed class FileText {
  const FileText();
}

/// The file's [text], read as written in [encoding].
final class TextRead extends FileText {
  const TextRead(this.text, this.encoding);

  final String text;
  final TextEncoding encoding;
}

/// Bytes that are neither UTF-8 nor Big5, such as a spreadsheet's own
/// file or a picture.
final class TextUnreadable extends FileText {
  const TextUnreadable();
}

/// The text of [bytes], a file to import: UTF-8 with or without a byte
/// order mark (the mark left out), else Big5 as Windows writes it
/// (cp950: what Excel saves a CSV in as 「ANSI」 on a Traditional Chinese
/// system). Bytes that are neither are [TextUnreadable], never guessed
/// into other characters.
FileText readFileText(List<int> bytes) {
  final marked =
      bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF;
  try {
    return TextRead(
      utf8.decode(marked ? bytes.sublist(3) : bytes),
      TextEncoding.utf8,
    );
  } on FormatException {
    // Not UTF-8: tried as Big5 below, unless it said it was UTF-8.
  }
  if (marked) return const TextUnreadable();
  final big5 = _big5(bytes);
  return big5 == null
      ? const TextUnreadable()
      : TextRead(big5, TextEncoding.big5);
}

/// [bytes] read as Big5 (cp950); null at a byte that is no character.
String? _big5(List<int> bytes) {
  final text = StringBuffer();
  for (var i = 0; i < bytes.length; i++) {
    final byte = bytes[i];
    if (byte < 0x80) {
      text.writeCharCode(byte);
      continue;
    }
    if (byte < _firstLead || byte > _lastLead || i + 1 >= bytes.length) {
      return null;
    }
    final trail = bytes[++i];
    final column = trail >= 0x40 && trail <= 0x7E
        ? trail - 0x40
        : trail >= 0xA1 && trail <= 0xFE
        ? trail - 0xA1 + _lowTrails
        : -1;
    if (column < 0) return null;
    final code = big5Characters.codeUnitAt(
      (byte - _firstLead) * _trails + column,
    );
    if (code == _none) return null;
    text.writeCharCode(code);
  }
  return text.toString();
}

/// The lead bytes [big5Characters] holds.
const _firstLead = 0xA1;
const _lastLead = 0xF9;

/// Trail bytes 0x40 to 0x7E, then 0xA1 to 0xFE.
const _lowTrails = 0x7E - 0x40 + 1;
const _trails = _lowTrails + 0xFE - 0xA1 + 1;

/// Where [big5Characters] has no character.
const _none = 0xFFFD;
